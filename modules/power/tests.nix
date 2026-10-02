{ pkgs }:
pkgs.runCommand "framework-power-tests-passed" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.json5 ])) ];
  src = ./.;
} ''
  export PYTHONDONTWRITEBYTECODE=1
  python -m unittest discover -s "$src/tests" -v
  printf 'Hardware-free Python regression suite passed. Real hardware remains unverified.\n' > "$out"
''
