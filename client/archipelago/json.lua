-- Use json.array() to encode an empty table as "[]" instead of "{}".
local json = {}

local ARRAY_MT = { __jsonarray = true }
function json.array(t) return setmetatable(t or {}, ARRAY_MT) end

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
                  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encodeString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function isArray(t)
  if getmetatable(t) == ARRAY_MT then return true end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n > 0 and n == #t
end

local encode
encode = function(v, out)
  local tv = type(v)
  if v == nil or v == json.null then
    out[#out + 1] = "null"
  elseif tv == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "null"
    elseif v == math.floor(v) and math.abs(v) < 2^53 then
      out[#out + 1] = string.format("%.0f", v)
    else
      out[#out + 1] = string.format("%.17g", v)
    end
  elseif tv == "string" then
    out[#out + 1] = encodeString(v)
  elseif tv == "table" then
    if isArray(v) then
      out[#out + 1] = "["
      for i = 1, #v do
        if i > 1 then out[#out + 1] = "," end
        encode(v[i], out)
      end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local first = true
      for k, val in pairs(v) do
        if not first then out[#out + 1] = "," end
        first = false
        out[#out + 1] = encodeString(tostring(k))
        out[#out + 1] = ":"
        encode(val, out)
      end
      out[#out + 1] = "}"
    end
  else
    error("json: cannot encode " .. tv)
  end
end

function json.encode(v)
  local out = {}
  encode(v, out)
  return table.concat(out)
end

json.null = setmetatable({}, { __tostring = function() return "null" end })

local byte, sub, find = string.byte, string.sub, string.find

local function decodeError(str, i, msg)
  error(string.format("json: %s at position %d near '%s'", msg, i, sub(str, i, i + 10)), 0)
end

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
                     0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local decodeValue

local function skip(str, i)
  local _, e = find(str, "^[ \n\r\t]*", i)
  return e + 1
end

local function decodeString(str, i)
  local parts, n = {}, 0
  local j = i + 1
  while true do
    local s, e = find(str, '["\\]', j)
    if not s then decodeError(str, i, "unterminated string") end
    n = n + 1; parts[n] = sub(str, j, s - 1)
    if byte(str, s) == 34 then return table.concat(parts), s + 1 end
    local c = sub(str, s + 1, s + 1)
    if c == "u" then
      local cp = tonumber(sub(str, s + 2, s + 5), 16)
      local nextj = s + 6
      if cp >= 0xD800 and cp <= 0xDBFF and sub(str, s + 6, s + 7) == "\\u" then
        local lo = tonumber(sub(str, s + 8, s + 11), 16)
        if lo and lo >= 0xDC00 and lo <= 0xDFFF then
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
          nextj = s + 12
        end
      end
      n = n + 1; parts[n] = utf8char(cp)
      j = nextj
    else
      local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
      n = n + 1; parts[n] = map[c] or c
      j = s + 2
    end
  end
end

decodeValue = function(str, i)
  i = skip(str, i)
  local c = byte(str, i)
  if c == 123 then
    local obj = {}
    i = skip(str, i + 1)
    if byte(str, i) == 125 then return obj, i + 1 end
    while true do
      i = skip(str, i)
      if byte(str, i) ~= 34 then decodeError(str, i, "expected key") end
      local key
      key, i = decodeString(str, i)
      i = skip(str, i)
      if byte(str, i) ~= 58 then decodeError(str, i, "expected ':'") end
      local val
      val, i = decodeValue(str, i + 1)
      obj[key] = val
      i = skip(str, i)
      local d = byte(str, i)
      if d == 125 then return obj, i + 1 end
      if d ~= 44 then decodeError(str, i, "expected ',' or '}'") end
      i = i + 1
    end
  elseif c == 91 then
    local arr, n = json.array({}), 0
    i = skip(str, i + 1)
    if byte(str, i) == 93 then return arr, i + 1 end
    while true do
      local val
      val, i = decodeValue(str, i)
      n = n + 1; arr[n] = val
      i = skip(str, i)
      local d = byte(str, i)
      if d == 93 then return arr, i + 1 end
      if d ~= 44 then decodeError(str, i, "expected ',' or ']'") end
      i = i + 1
    end
  elseif c == 34 then
    return decodeString(str, i)
  elseif c == 116 and sub(str, i, i + 3) == "true" then
    return true, i + 4
  elseif c == 102 and sub(str, i, i + 4) == "false" then
    return false, i + 5
  elseif c == 110 and sub(str, i, i + 3) == "null" then
    return nil, i + 4
  else
    local s, e = find(str, "^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not s then decodeError(str, i, "unexpected character") end
    return tonumber(sub(str, s, e)), e + 1
  end
end

function json.decode(str)
  local v = decodeValue(str, 1)
  return v
end

return json
