# Reads a Go coverage profile (go test -coverprofile) into records:
#   S <block> <statements> <count>         one per block, for statement coverage
#   L <path> <line> <count> <partial>      one per line a block spans
# Paths are made relative to the repository by swapping the module path for the module's directory (prefix). A path
# outside the module is kept as is and marked partial, to be matched by suffix.
#
# Variables: module (from go.mod), prefix (the module's directory relative to the repository, with a trailing slash)
BEGIN { OFS = "\t" }
/^mode:/ || NF != 3 { next }
{
  pos = length($1)
  while (pos > 0 && substr($1, pos, 1) != ":") pos--
  if (pos == 0) next
  file = substr($1, 1, pos - 1)
  range = substr($1, pos + 1)
  split(range, r, ",")
  split(r[1], s, ".")
  split(r[2], e, ".")

  partial = 0
  if (module != "" && index(file, module "/") == 1) file = prefix substr(file, length(module) + 2)
  else partial = 1

  print "S", file ":" range, $2, $3
  for (l = s[1] + 0; l <= e[1] + 0; l++) print "L", file, l, $3, partial
}
