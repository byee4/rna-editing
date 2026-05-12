rule run_downstream_parsers:
    input:
        reditools=expand("results/tools/{aligner}/reditools/{condition}_{sample}.output",
                         aligner=_ALIGNERS, condition=config["conditions"], sample=config["samples"]),
        sprint=expand("results/tools/{aligner}/sprint/{condition}_{sample}_output",
                      aligner=_ALIGNERS, condition=config["conditions"], sample=config["samples"]),
        redml=expand("results/tools/{aligner}/red_ml/{condition}_{sample}_output",
                     aligner=_ALIGNERS, condition=config["conditions"], sample=config["samples"]),
        bcftools=expand("results/tools/{aligner}/bcftools/{condition}_{sample}.bcf",
                        aligner=_ALIGNERS, condition=config["conditions"], sample=config["samples"]),
        jacusa=expand("results/tools/{aligner}/jacusa2/Jacusa.out", aligner=_ALIGNERS)
    output:
        touch("results/downstream/parsers.done"),
        "results/downstream/Data_REDItool2.json",
        "results/downstream/Data_SPRINT.json",
        "results/downstream/Data_REDML.json",
        "results/downstream/Data_BCFTools.json",
        "results/downstream/Data_JACUSA2.json",
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 32000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/run_downstream_parsers.out",
        stderr="results/logs/run_downstream_parsers.err"
    params:
        downstream_dir=config["downstream_scripts_dir"],
        db_path=config["references"]["db_path"],
        aligners=",".join(_ALIGNERS)
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DB_PATH={params.db_path}
        BENCH_DIR="$WORKDIR/results/downstream"
        export BENCH_DIR
        PATCHDIR=$(mktemp -d)

        IFS=',' read -ra ALIGNERS <<< "{params.aligners}"
        export _ALIGNERS="{params.aligners}"

        # Write the aligner patcher once
        cat > "$PATCHDIR/patch_aligners.py" << 'PATCHER'
import re, sys, os
s, o = sys.argv[1], sys.argv[2]
aligners = os.environ['_ALIGNERS'].split(',')
with open(s) as f:
    code = f.read()
code = re.sub(r"aligners\s*=\s*\[(?!\[)[^\]]*\]", "aligners = " + repr(aligners), code)
code = re.sub(r"aligners\s*=\s*\[\[.*?\]\]",
              "aligners = [" + repr(aligners) + ", " + repr(aligners) + "]",
              code, flags=re.DOTALL)
with open(o, 'w') as f:
    f.write(code)
PATCHER

        # Build staging directories expected by Downstream scripts:
        # each script uses path = "../TOOL" relative to Downstream/
        rm -rf "$BENCH_DIR/REDItools2" "$BENCH_DIR/SPRINT" "$BENCH_DIR/REDML" \
               "$BENCH_DIR/BCFTools" "$BENCH_DIR/JACUSA2"

        for aligner in "${{ALIGNERS[@]}}"; do
            mkdir -p "$BENCH_DIR/REDItools2/$aligner" "$BENCH_DIR/SPRINT/$aligner" \
                     "$BENCH_DIR/REDML/$aligner" "$BENCH_DIR/BCFTools/$aligner" "$BENCH_DIR/JACUSA2/$aligner"

            # REDItools2: symlink with _filt_sortrmdup suffix REDItools2.py expects
            for f in results/tools/$aligner/reditools/*.output; do
                [ -e "$f" ] || continue
                base=$(basename "$f" .output)
                ln -sf "$WORKDIR/$f" "$BENCH_DIR/REDItools2/$aligner/${{base}}_filt_sortrmdup.output"
            done

            # SPRINT: symlink with _filt_sortrmdup_output suffix SPRINT.py expects
            for d in results/tools/$aligner/sprint/*_output; do
                [ -e "$d" ] || continue
                base=$(basename "$d")
                ln -sf "$WORKDIR/$d" "$BENCH_DIR/SPRINT/$aligner/${{base%_output}}_filt_sortrmdup_output"
            done

            # REDML: symlink output dirs (REDML.py expects CONDITION_CLONE_output naming)
            for d in results/tools/$aligner/red_ml/*_output; do
                [ -e "$d" ] || continue
                ln -sf "$WORKDIR/$d" "$BENCH_DIR/REDML/$aligner/$(basename $d)"
            done

            # BCFtools: convert BCF to VCF; vcf2bed is done in Python by BCFtools.py
            for f in results/tools/$aligner/bcftools/*.bcf; do
                [ -e "$f" ] || continue
                base=$(basename "$f" .bcf)
                bcftools view "$f" > "$BENCH_DIR/BCFTools/$aligner/${{base}}.vcf"
            done

            # JACUSA2: link raw output; per-threshold preprocessing done by JACUSA2.py
            ln -sf "$WORKDIR/results/tools/$aligner/jacusa2/Jacusa.out" \
                   "$BENCH_DIR/JACUSA2/$aligner/Jacusa.out"
        done

        LOG_OUT="$WORKDIR/{log.stdout}"
        LOG_ERR="$WORKDIR/{log.stderr}"

        cd {params.downstream_dir}

        for script in REDItools2.py SPRINT.py REDML.py BCFtools.py JACUSA2.py; do
            python3 "$PATCHDIR/patch_aligners.py" "$script" "$PATCHDIR/$script"
            python3 -c "exec(open('$PATCHDIR/$script').read())" 1>> "$LOG_OUT" 2>> "$LOG_ERR"
        done
        """


rule update_alu:
    input:
        "results/downstream/parsers.done"
    output:
        touch("results/downstream/alu_updated.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 90 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/update_alu.out",
        stderr="results/logs/update_alu.err"
    params:
        downstream_dir=config["downstream_scripts_dir"],
        db_path=config["references"]["db_path"],
        aligners=",".join(_ALIGNERS)
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DB_PATH={params.db_path}
        export DOWNSTREAM_WORKDIR="$WORKDIR/results/downstream/"
        PATCHDIR=$(mktemp -d)
        export _ALIGNERS="{params.aligners}"

        cat > "$PATCHDIR/patch_aligners.py" << 'PATCHER'
import re, sys, os
s, o = sys.argv[1], sys.argv[2]
aligners = os.environ['_ALIGNERS'].split(',')
with open(s) as f:
    code = f.read()
code = re.sub(r"aligners\s*=\s*\[(?!\[)[^\]]*\]", "aligners = " + repr(aligners), code)
code = re.sub(r"aligners\s*=\s*\[\[.*?\]\]",
              "aligners = [" + repr(aligners) + ", " + repr(aligners) + "]",
              code, flags=re.DOTALL)
with open(o, 'w') as f:
    f.write(code)
PATCHER

        cd {params.downstream_dir}
        python3 "$PATCHDIR/patch_aligners.py" "Alu.py" "$PATCHDIR/Alu.py"
        python3 -c "exec(open('$PATCHDIR/Alu.py').read())" \
            1> "$WORKDIR/{log.stdout}" 2> "$WORKDIR/{log.stderr}"
        """


rule individual_analysis:
    input:
        "results/downstream/alu_updated.done"
    output:
        touch("results/downstream/individual_analysis.done"),
        "results/downstream/Downstream/IndividualCompare.png",
        "results/downstream/Downstream/REDItools2_Table.csv",
        "results/downstream/Downstream/SPRINT_Table.csv",
        "results/downstream/Downstream/REDML_Table.csv",
        "results/downstream/Downstream/BCFTools_Table.csv",
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 90 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/individual_analysis.out",
        stderr="results/logs/individual_analysis.err"
    params:
        downstream_dir=config["downstream_scripts_dir"],
        aligners=",".join(_ALIGNERS)
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DOWNSTREAM_WORKDIR="$WORKDIR/results/downstream/"
        export DOWNSTREAM_OUTDIR="$WORKDIR/results/downstream/Downstream/"
        mkdir -p "$DOWNSTREAM_OUTDIR"
        PATCHDIR=$(mktemp -d)
        export _ALIGNERS="{params.aligners}"

        cat > "$PATCHDIR/patch_aligners.py" << 'PATCHER'
import re, sys, os
s, o = sys.argv[1], sys.argv[2]
aligners = os.environ['_ALIGNERS'].split(',')
with open(s) as f:
    code = f.read()
code = re.sub(r"aligners\s*=\s*\[(?!\[)[^\]]*\]", "aligners = " + repr(aligners), code)
code = re.sub(r"aligners\s*=\s*\[\[.*?\]\]",
              "aligners = [" + repr(aligners) + ", " + repr(aligners) + "]",
              code, flags=re.DOTALL)
with open(o, 'w') as f:
    f.write(code)
PATCHER

        cd {params.downstream_dir}
        python3 "$PATCHDIR/patch_aligners.py" "Individual-Analysis.py" \
                "$PATCHDIR/Individual-Analysis.py"
        python3 -c "exec(open('$PATCHDIR/Individual-Analysis.py').read())" \
            1> "$WORKDIR/{log.stdout}" 2> "$WORKDIR/{log.stderr}"
        """


rule reanalysis_multiple:
    input:
        "results/downstream/individual_analysis.done"
    output:
        touch("results/downstream/reanalysis_multiple.done"),
        "results/downstream/Data_REDItools2-Multiple.json",
        "results/downstream/Data_SPRINT-Multiple.json",
        "results/downstream/Data_BCFTools-Multiple.json",
        "results/downstream/Data_REDML-Multiple.json",
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 32000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/reanalysis_multiple.out",
        stderr="results/logs/reanalysis_multiple.err"
    params:
        downstream_dir=config["downstream_scripts_dir"],
        db_path=config["references"]["db_path"],
        aligners=",".join(_ALIGNERS)
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DB_PATH={params.db_path}
        export DOWNSTREAM_WORKDIR="$WORKDIR/results/downstream/"
        PATCHDIR=$(mktemp -d)
        export _ALIGNERS="{params.aligners}"

        cat > "$PATCHDIR/patch_aligners.py" << 'PATCHER'
import re, sys, os
s, o = sys.argv[1], sys.argv[2]
aligners = os.environ['_ALIGNERS'].split(',')
with open(s) as f:
    code = f.read()
code = re.sub(r"aligners\s*=\s*\[(?!\[)[^\]]*\]", "aligners = " + repr(aligners), code)
code = re.sub(r"aligners\s*=\s*\[\[.*?\]\]",
              "aligners = [" + repr(aligners) + ", " + repr(aligners) + "]",
              code, flags=re.DOTALL)
with open(o, 'w') as f:
    f.write(code)
PATCHER

        cd {params.downstream_dir}
        python3 "$PATCHDIR/patch_aligners.py" "Re-Analysis-Multiple.py" \
                "$PATCHDIR/Re-Analysis-Multiple.py"
        python3 -c "exec(open('$PATCHDIR/Re-Analysis-Multiple.py').read())" \
            1> "$WORKDIR/{log.stdout}" 2> "$WORKDIR/{log.stderr}"
        """


rule multiple_analysis:
    input:
        "results/downstream/reanalysis_multiple.done"
    output:
        touch("results/downstream/multiple_analysis.done"),
        "results/downstream/Downstream/MultipleCompare.png",
        "results/downstream/Downstream/REDItools2-Multiple_Table.csv",
        "results/downstream/Downstream/SPRINT-Multiple_Table.csv",
        "results/downstream/Downstream/REDML-Multiple_Table.csv",
        "results/downstream/Downstream/BCFTools-Multiple_Table.csv",
        "results/downstream/Downstream/JACUSA2_Table.csv",
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 90 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/multiple_analysis.out",
        stderr="results/logs/multiple_analysis.err"
    params:
        downstream_dir=config["downstream_scripts_dir"],
        aligners=",".join(_ALIGNERS)
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DOWNSTREAM_WORKDIR="$WORKDIR/results/downstream/"
        export DOWNSTREAM_OUTDIR="$WORKDIR/results/downstream/Downstream/"
        mkdir -p "$DOWNSTREAM_OUTDIR"
        PATCHDIR=$(mktemp -d)
        export _ALIGNERS="{params.aligners}"

        cat > "$PATCHDIR/patch_aligners.py" << 'PATCHER'
import re, sys, os
s, o = sys.argv[1], sys.argv[2]
aligners = os.environ['_ALIGNERS'].split(',')
with open(s) as f:
    code = f.read()
code = re.sub(r"aligners\s*=\s*\[(?!\[)[^\]]*\]", "aligners = " + repr(aligners), code)
code = re.sub(r"aligners\s*=\s*\[\[.*?\]\]",
              "aligners = [" + repr(aligners) + ", " + repr(aligners) + "]",
              code, flags=re.DOTALL)
with open(o, 'w') as f:
    f.write(code)
PATCHER

        cd {params.downstream_dir}
        python3 "$PATCHDIR/patch_aligners.py" "Multiple-Analysis.py" \
                "$PATCHDIR/Multiple-Analysis.py"
        python3 -c "exec(open('$PATCHDIR/Multiple-Analysis.py').read())" \
            1> "$WORKDIR/{log.stdout}" 2> "$WORKDIR/{log.stderr}"
        """
