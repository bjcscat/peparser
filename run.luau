local fs = require("@lute/fs")

local r = fs.open("./coverage.out", "r+")

print(fs.read(r))