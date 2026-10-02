-- WinHTTP handles TLS itself, so both ws:// and wss:// work without shipping any DLLs (Windows 8+).
local ffi = require("ffi")

pcall(ffi.cdef, [[
typedef void* GC_HINTERNET;
void* WinHttpOpen(const uint16_t* agent, unsigned long accessType, const uint16_t* proxy, const uint16_t* bypass, unsigned long flags);
void* WinHttpConnect(void* session, const uint16_t* server, unsigned short port, unsigned long reserved);
void* WinHttpOpenRequest(void* connect, const uint16_t* verb, const uint16_t* object, const uint16_t* version, const uint16_t* referrer, const uint16_t** acceptTypes, unsigned long flags);
int WinHttpSetOption(void* handle, unsigned long option, void* buffer, unsigned long length);
int WinHttpSetTimeouts(void* handle, int resolve, int connect, int send, int receive);
int WinHttpSendRequest(void* request, const uint16_t* headers, unsigned long headersLength, void* optional, unsigned long optionalLength, unsigned long totalLength, uintptr_t context);
int WinHttpReceiveResponse(void* request, void* reserved);
int WinHttpQueryHeaders(void* request, unsigned long infoLevel, const uint16_t* name, void* buffer, unsigned long* bufferLength, unsigned long* index);
void* WinHttpWebSocketCompleteUpgrade(void* request, uintptr_t context);
unsigned long WinHttpWebSocketSend(void* ws, int bufferType, const char* buffer, unsigned long length);
unsigned long WinHttpWebSocketReceive(void* ws, void* buffer, unsigned long length, unsigned long* bytesRead, int* bufferType);
unsigned long WinHttpWebSocketClose(void* ws, unsigned short status, void* reason, unsigned long reasonLength);
int WinHttpCloseHandle(void* handle);
unsigned long GetLastError(void);
]])

local lib = ffi.load("winhttp")
local kernel32 = ffi.C

local M = { lib = lib }

M.ACCESS_TYPE_DEFAULT_PROXY   = 0
M.ACCESS_TYPE_AUTOMATIC_PROXY = 4
M.FLAG_SECURE                 = 0x00800000
M.OPTION_UPGRADE_TO_WEB_SOCKET = 114
M.QUERY_STATUS_CODE           = 19
M.QUERY_FLAG_NUMBER           = 0x20000000
M.BUFFER_BINARY_MESSAGE       = 0
M.BUFFER_BINARY_FRAGMENT      = 1
M.BUFFER_UTF8_MESSAGE         = 2
M.BUFFER_UTF8_FRAGMENT        = 3
M.BUFFER_CLOSE                = 4

function M.wide(s)
  local n = #s
  local buf = ffi.new("uint16_t[?]", n + 1)
  for i = 1, n do buf[i - 1] = s:byte(i) end
  buf[n] = 0
  return buf
end

function M.lastError()
  return tonumber(kernel32.GetLastError())
end

function M.handleToNumber(h)
  return tonumber(ffi.cast("uintptr_t", h))
end

function M.numberToHandle(n)
  return ffi.cast("void*", ffi.cast("uintptr_t", n))
end

function M.open(host, port, secure, path)
  local session = lib.WinHttpOpen(M.wide("GravityCircuitAP/0.1"), M.ACCESS_TYPE_AUTOMATIC_PROXY, nil, nil, 0)
  if session == nil then
    session = lib.WinHttpOpen(M.wide("GravityCircuitAP/0.1"), M.ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0)
  end
  if session == nil then return nil, "WinHttpOpen failed (" .. M.lastError() .. ")" end
  -- infinite receive timeout: the AP server can be silent for a long time
  lib.WinHttpSetTimeouts(session, 10000, 10000, 10000, 0)

  local connect = lib.WinHttpConnect(session, M.wide(host), port, 0)
  if connect == nil then
    local err = M.lastError()
    lib.WinHttpCloseHandle(session)
    return nil, "WinHttpConnect failed (" .. err .. ")"
  end

  local flags = secure and M.FLAG_SECURE or 0
  local request = lib.WinHttpOpenRequest(connect, M.wide("GET"), M.wide(path or "/"), nil, nil, nil, flags)
  local function fail(what)
    local err = M.lastError()
    if request ~= nil then lib.WinHttpCloseHandle(request) end
    lib.WinHttpCloseHandle(connect)
    lib.WinHttpCloseHandle(session)
    return nil, what .. " failed (" .. err .. ")"
  end
  if request == nil then return fail("WinHttpOpenRequest") end
  if lib.WinHttpSetOption(request, M.OPTION_UPGRADE_TO_WEB_SOCKET, nil, 0) == 0 then
    return fail("WebSocket upgrade option")
  end
  if lib.WinHttpSendRequest(request, nil, 0, nil, 0, 0, 0) == 0 then return fail("WinHttpSendRequest") end
  if lib.WinHttpReceiveResponse(request, nil) == 0 then return fail("WinHttpReceiveResponse") end

  local status = ffi.new("unsigned long[1]")
  local size = ffi.new("unsigned long[1]", ffi.sizeof("unsigned long"))
  lib.WinHttpQueryHeaders(request, M.QUERY_STATUS_CODE + M.QUERY_FLAG_NUMBER, nil, status, size, nil)
  if status[0] ~= 101 then
    local code = tonumber(status[0])
    lib.WinHttpCloseHandle(request)
    lib.WinHttpCloseHandle(connect)
    lib.WinHttpCloseHandle(session)
    return nil, "server answered HTTP " .. code .. " instead of a websocket upgrade"
  end

  local ws = lib.WinHttpWebSocketCompleteUpgrade(request, 0)
  if ws == nil then return fail("WinHttpWebSocketCompleteUpgrade") end
  lib.WinHttpCloseHandle(request)
  return ws, session, connect
end

return M
