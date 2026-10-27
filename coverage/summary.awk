# Joins the coverage records (first file) with the changed lines (second file) and prints:
#   TOTAL <statements|lines> <covered> <total>
#   CHANGED <covered> <total>              changed lines the reports count as coverable
#   UNCOVERED <path> <ranges>              per file, in diff order: 12-14, 20
# Several reports may cover the same line (a module's report and an aggregate); a line is covered when any says so.
# Go profiles are measured by statement, the way `go tool cover` reports them; everything else by line.
function resolve(path,   i, rest) {
  if (path in exact) return path
  rest = path
  while ((i = index(rest, "/")) > 0) {
    rest = substr(rest, i + 1)
    if (rest in partial) return rest
  }
  return ""
}
function close_range(f) {
  if (!(f in from)) return
  uncovered[f] = uncovered[f] (uncovered[f] == "" ? "" : ", ") from[f] (to[f] > from[f] ? "-" to[f] : "")
  delete from[f]
}
BEGIN { FS = OFS = "\t" }
FILENAME == ARGV[1] {
  if ($1 == "S") {
    if (!($2 in count) || $4 + 0 > count[$2]) count[$2] = $4 + 0
    stmts[$2] = $3 + 0
  } else if ($1 == "L") {
    k = $2 SUBSEP $3
    if (!(k in hits) || $4 + 0 > hits[k]) hits[k] = $4 + 0
    if ($5 == 1) partial[$2] = 1
    else exact[$2] = 1
  }
  next
}
{
  f = $1
  if (!(f in resolved)) resolved[f] = resolve(f)
  k = resolved[f] SUBSEP $2
  if (resolved[f] == "" || !(k in hits)) next
  changed++
  if (hits[k] > 0) { changed_covered++; next }
  if (!(f in seen)) { seen[f] = 1; files[++nfiles] = f }
  if ((f in from) && $2 == to[f] + 1) { to[f] = $2; next }
  close_range(f)
  from[f] = to[f] = $2
}
END {
  kind = "lines"
  for (k in count) {
    kind = "statements"
    total += stmts[k]
    if (count[k] > 0) covered += stmts[k]
  }
  if (kind == "lines") for (k in hits) { total++; if (hits[k] > 0) covered++ }
  print "TOTAL", kind, covered + 0, total + 0
  print "CHANGED", changed_covered + 0, changed + 0
  for (i = 1; i <= nfiles; i++) {
    close_range(files[i])
    print "UNCOVERED", files[i], uncovered[files[i]]
  }
}
