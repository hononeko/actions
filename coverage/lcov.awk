# Reads an lcov report (Bun, Vitest, Jest, c8, ...) into records:
#   L <path> <line> <hits> <partial>
# Paths are made relative to the repository: an absolute path loses the repository's root (top), a relative one,
# relative to where the tests ran, gains that directory (prefix).
#
# Variables: top (the repository's root), prefix (the working directory relative to it, with a trailing slash)
BEGIN { OFS = "\t" }
/^SF:/ {
  file = substr($0, 4)
  sub(/\r$/, "", file)
  if (index(file, top "/") == 1) file = substr(file, length(top) + 2)
  else if (substr(file, 1, 1) != "/") {
    while (substr(file, 1, 2) == "./") file = substr(file, 3)
    file = prefix file
  }
  next
}
/^DA:/ && file != "" {
  split(substr($0, 4), d, ",")
  print "L", file, d[1] + 0, d[2] + 0, 0
  next
}
/^end_of_record/ { file = "" }
