# Runs extra/benchmarks/bench_journals.rb alternately on several git refs
# and prints the median of the run medians as a markdown table.
#
# usage: python3 compare_journal_benchmark.py BENCH_SCRIPT ROUNDS REF...
import os
import re
import statistics
import subprocess
import sys

script, rounds, refs = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
out_dir = os.environ.get('BENCH_OUT', '.')
data, results, header = {}, {}, ''
for r in range(rounds):
    for ref in refs:
        subprocess.run(['git', 'checkout', '-q', '--detach', ref], check=True)
        proc = subprocess.run(['bin/rails', 'r', script], capture_output=True, text=True)
        name = re.sub(r'\W', '_', ref)
        with open(os.path.join(out_dir, f'bench_{name}_{r + 1}.txt'), 'w') as f:
            f.write(proc.stdout + proc.stderr)
        if proc.returncode != 0:
            sys.exit(f'benchmark failed on {ref}:\n{proc.stderr[-3000:]}')
        for line in proc.stdout.splitlines():
            if line.startswith('variant='):
                header = re.sub(r'variant=\S+ ', '', line)
            m = re.match(r'(\w+)\s+(admin|member|anonymous)\s+([\d.]+)\s+[\d.]+\s+[\d.]+\s+(\d+)', line)
            if m:
                data.setdefault((m[1], m[2]), {}).setdefault(ref, []).append(float(m[3]))
                results.setdefault((m[1], m[2]), set()).add(m[4])
        print(f'round {r + 1}/{rounds} {ref} done', file=sys.stderr, flush=True)

print(f'`{header} rounds={rounds}`\n')
print('| benchmark | user | ' + ' | '.join(f'{ref} (ms)' for ref in refs) + ' | ratio | same result |')
print('|---|---|' + '---:|' * len(refs) + '---:|:---:|')
for (bench, user), values in data.items():
    medians = [statistics.median(values[ref]) for ref in refs]
    ratio = medians[-1] / medians[0] if medians[0] else 0
    same = 'yes' if len(results[(bench, user)]) == 1 else '**NO**'
    print(f'| {bench} | {user} | ' + ' | '.join(f'{m:.2f}' for m in medians) + f' | {ratio:.2f} | {same} |')
