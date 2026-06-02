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
        jacusa=(expand("results/tools/{aligner}/jacusa2/Jacusa.out", aligner=_ALIGNERS)
                if _RUN_JACUSA2 else [])
    output:
        touch("results/downstream/parsers.done"),
        "results/downstream/Data_REDItool2.json",
        "results/downstream/Data_SPRINT.json",
        "results/downstream/Data_REDML.json",
        "results/downstream/Data_BCFTools.json",
        data_jacusa=(["results/downstream/Data_JACUSA2.json"] if _RUN_JACUSA2 else []),
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
        aligners=",".join(_ALIGNERS),
        tmpdir=config.get("tmpdir", "/tmp"),
        run_jacusa2=("1" if _RUN_JACUSA2 else "0"),
        jac_cond1=_JAC_C1,
        jac_cond2=_JAC_C2,
        parser_scripts=("REDItools2.py SPRINT.py REDML.py BCFtools.py JACUSA2.py"
                        if _RUN_JACUSA2 else "REDItools2.py SPRINT.py REDML.py BCFtools.py")
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DB_PATH={params.db_path}
        export TMPDIR={params.tmpdir}
        export RUN_JACUSA2={params.run_jacusa2}
        export JAC_COND1={params.jac_cond1}
        export JAC_COND2={params.jac_cond2}
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
# rna-editing-49s: HISAT2 was aligned to a chr-prefixed reference, so the parsers'
# unconditional "chr" prepend produced chrchr1 -> zero REDIportal/Alu overlap.
# Make the prepend idempotent so chr-prefixed contigs are left untouched.
code = code.replace(
    "line[0] = 'chr' + line[0]",
    "line[0] = line[0] if line[0].startswith('chr') else 'chr' + line[0]")
# rna-editing-5uz: JACUSA2 parser dropped any site lacking an ALT in either
# condition (exactly the WT-edited/KO-unedited ADAR signal), collapsing WT==KO.
# Keep sites edited in only one condition and count them toward that condition.
code = code.replace(
    "    df_filt = df_filt.dropna(subset=['wt', 'adarko'])",
    "    df_filt = df_filt.dropna(subset=['wt', 'adarko'], how='all')\n"
    "    df_filt['wt'] = df_filt['wt'].fillna('')\n"
    "    df_filt['adarko'] = df_filt['adarko'].fillna('')")
# pd.to_csv writes '' for empty strings; pd.read_csv re-reads them as NaN.
# Add fillna at WTID/ADARID construction so .str.replace never sees a float.
code = code.replace(
    "data['wt'].str.replace('->', '')",
    "data['wt'].fillna('').str.replace('->', '')")
code = code.replace(
    "data['adarko'].str.replace('->', '')",
    "data['adarko'].fillna('').str.replace('->', '')")
# rna-editing-51k: re-key the JACUSA2 export to the real condition names. The 'wt'
# column is bases1* (= condition1) and 'adarko' is bases2* (= condition2), so the
# positional keys map condition1 -> 'WT' slot and condition2 -> 'ADAR1KO' slot.
_c1 = os.environ.get('JAC_COND1', 'WT')
_c2 = os.environ.get('JAC_COND2', 'ADAR1KO')
code = code.replace("conditions = ['WT', 'ADAR1KO']",
                    "conditions = [%r, %r]" % (_c1, _c2))
# Swap-safe via sentinels (condition names may be the reverse of WT/ADAR1KO).
code = code.replace("export_data[align]['WT'][cutoff]", "export_data[align]['__JC1__'][cutoff]")
code = code.replace("export_data[align]['ADAR1KO'][cutoff]", "export_data[align]['__JC2__'][cutoff]")
code = code.replace("export_data[align]['__JC1__'][cutoff]", "export_data[align][%r][cutoff]" % _c1)
code = code.replace("export_data[align]['__JC2__'][cutoff]", "export_data[align][%r][cutoff]" % _c2)
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
            if [ "$RUN_JACUSA2" = "1" ]; then
                ln -sf "$WORKDIR/results/tools/$aligner/jacusa2/Jacusa.out" \
                       "$BENCH_DIR/JACUSA2/$aligner/Jacusa.out"
            fi
        done

        LOG_OUT="$WORKDIR/{log.stdout}"
        LOG_ERR="$WORKDIR/{log.stderr}"

        cd {params.downstream_dir}

        for script in {params.parser_scripts}; do
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
        aligners=",".join(_ALIGNERS),
        tmpdir=config.get("tmpdir", "/tmp")
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DB_PATH={params.db_path}
        export TMPDIR={params.tmpdir}
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
        aligners=",".join(_ALIGNERS),
        tmpdir=config.get("tmpdir", "/tmp")
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export TMPDIR={params.tmpdir}
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
        aligners=",".join(_ALIGNERS),
        tmpdir=config.get("tmpdir", "/tmp")
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DB_PATH={params.db_path}
        export TMPDIR={params.tmpdir}
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
        data_jacusa=(["results/downstream/Downstream/JACUSA2_Table.csv"] if _RUN_JACUSA2 else []),
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
        aligners=",".join(_ALIGNERS),
        tmpdir=config.get("tmpdir", "/tmp"),
        run_jacusa2=("1" if _RUN_JACUSA2 else "0"),
        jac_cond1=_JAC_C1,
        jac_cond2=_JAC_C2
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export TMPDIR={params.tmpdir}
        export RUN_JACUSA2={params.run_jacusa2}
        export JAC_COND1={params.jac_cond1}
        export JAC_COND2={params.jac_cond2}
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
# rna-editing-zhh: when JACUSA2 is disabled, drop it from the combined figure so
# Multiple-Analysis.py does not require the (absent) Data_JACUSA2.json / JACUSA2_Table.csv.
if os.environ.get('RUN_JACUSA2', '1') != '1':
    code = code.replace(
        "tools = ['BCFTools', 'RED-ML', 'SPRINT', 'REDItools2', 'JACUSA2']",
        "tools = ['BCFTools', 'RED-ML', 'SPRINT', 'REDItools2']")
    code = code.replace(
        "jacusa = load_database(path, 'Data_JACUSA2.json')", "jacusa = {{}}")
    code = code.replace(
        "for _align in aligners[0]:\n"
        "    for _cond in conditions:\n"
        "        for _cut in thresholds[0]:\n"
        "            _d = jacusa[_align][_cond][_cut]\n"
        "            _d.setdefault('N_res', _d.get('N_RES', 0))\n"
        "            _d.setdefault('N_db',  _d.get('N_REDIportal', 0))\n",
        "")
    code = code.replace(
        "save_to_csv_multiple('JACUSA2_Table.csv', jacusa, aligners[0], conditions, thresholds[0])\n",
        "")
    code = code.replace(
        "jacusaTable = pd.read_csv('JACUSA2_Table.csv').to_dict(orient='list')",
        "jacusaTable = {{}}")
    code = code.replace(
        "create_plot_for_Jacusa  (prepare_for_jacusa(jacusaTable, aligners=aligners[0]), 'Jacusa2', aligners[0], 'JACUSA2')\n",
        "")
    code = code.replace(
        "           'REDItools2':reditoolsTable,\n            'JACUSA2':jacusaTable}}",
        "           'REDItools2':reditoolsTable}}")
    code = code.replace("np.arange(5)", "np.arange(len(tools))")
else:
    # rna-editing-51k: JACUSA2 enabled -> label conditions list, figure panels, and
    # the panel assignment with the real condition1/condition2 names so any ordering
    # reads truthfully (condition1 -> left panel, condition2 -> right panel).
    _c1 = os.environ.get('JAC_COND1', 'WT')
    _c2 = os.environ.get('JAC_COND2', 'ADAR1KO')
    code = code.replace("conditions = ['WT', 'ADAR1KO']",
                        "conditions = [%r, %r]" % (_c1, _c2))
    # Swap-safe relabel of the two panel titles via sentinels.
    code = code.replace("'WT condition'", "'__JAC_C1_LABEL__'")
    code = code.replace("'ADAR1KO condition'", "'__JAC_C2_LABEL__'")
    code = code.replace("'__JAC_C1_LABEL__'", "%r" % (_c1 + ' condition'))
    code = code.replace("'__JAC_C2_LABEL__'", "%r" % (_c2 + ' condition'))
    # condition2 occupies the right panel (posy=1); condition1 stays on the left.
    code = code.replace("if condition == 'ADAR1KO':", "if condition == %r:" % _c2)
with open(o, 'w') as f:
    f.write(code)
PATCHER

        cd {params.downstream_dir}
        python3 "$PATCHDIR/patch_aligners.py" "Multiple-Analysis.py" \
                "$PATCHDIR/Multiple-Analysis.py"
        python3 -c "exec(open('$PATCHDIR/Multiple-Analysis.py').read())" \
            1> "$WORKDIR/{log.stdout}" 2> "$WORKDIR/{log.stderr}"
        """
