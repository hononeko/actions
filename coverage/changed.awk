# Reads `git diff --unified=0` into one "<path> <line>" record per added or changed line, paths relative to the
# repository.
BEGIN { OFS = "\t" }
/^\+\+\+ / {
  file = substr($0, 5)
  if (file == "/dev/null") file = ""
  else if (substr(file, 1, 2) == "b/") file = substr(file, 3)
  next
}
/^@@ / && file != "" {
  # @@ -<old>[,<n>] +<start>[,<count>] @@
  parts = split(substr($3, 2), p, ",")
  count = parts > 1 ? p[2] + 0 : 1
  for (i = 0; i < count; i++) print file, p[1] + i
}
