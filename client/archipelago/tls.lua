-- TLS client over a LuaSocket tcp object, using Windows' Schannel through the FFI. Wine implements Schannel
-- too, so this also gives wss:// under Proton. TLS 1.2 only, with normal certificate validation.
local ffi = require("ffi")
local bit = require("bit")
local socket = require("socket")

pcall(ffi.cdef, [[
typedef struct { uintptr_t dwLower; uintptr_t dwUpper; } GC_SecHandle;
typedef struct { unsigned long cbBuffer; unsigned long BufferType; void* pvBuffer; } GC_SecBuffer;
typedef struct { unsigned long ulVersion; unsigned long cBuffers; GC_SecBuffer* pBuffers; } GC_SecBufferDesc;
typedef struct {
  unsigned long dwVersion; unsigned long cCreds; void* paCred; void* hRootStore;
  unsigned long cMappers; void* aphMappers; unsigned long cSupportedAlgs; void* palgSupportedAlgs;
  unsigned long grbitEnabledProtocols; unsigned long dwMinimumCipherStrength; unsigned long dwMaximumCipherStrength;
  unsigned long dwSessionLifespan; unsigned long dwFlags; unsigned long dwCredFormat;
} GC_SCHANNEL_CRED;
typedef struct {
  unsigned long cbHeader; unsigned long cbTrailer; unsigned long cbMaximumMessage;
  unsigned long cBuffers; unsigned long cbBlockSize;
} GC_StreamSizes;
long AcquireCredentialsHandleA(const char*, const char*, unsigned long, void*, void*, void*, void*,
                               GC_SecHandle*, int64_t*);
long InitializeSecurityContextA(GC_SecHandle*, GC_SecHandle*, const char*, unsigned long, unsigned long,
                                unsigned long, GC_SecBufferDesc*, unsigned long, GC_SecHandle*, GC_SecBufferDesc*,
                                unsigned long*, int64_t*);
long QueryContextAttributesA(GC_SecHandle*, unsigned long, void*);
long EncryptMessage(GC_SecHandle*, unsigned long, GC_SecBufferDesc*, unsigned long);
long DecryptMessage(GC_SecHandle*, GC_SecBufferDesc*, unsigned long, unsigned long*);
long FreeContextBuffer(void*);
long DeleteSecurityContext(GC_SecHandle*);
long FreeCredentialsHandle(GC_SecHandle*);
]])

local ok, sspi = pcall(ffi.load, "secur32")
local M = { available = ok and ffi.os == "Windows" }
if not M.available then return M end

local SEC_E_OK = 0
local SEC_I_CONTINUE_NEEDED = 0x00090312
local SEC_I_CONTEXT_EXPIRED = 0x00090317
local SEC_I_RENEGOTIATE = 0x00090321
local SEC_E_INCOMPLETE_MESSAGE = bit.tobit(0x80090318)

local SECBUFFER_EMPTY, SECBUFFER_DATA, SECBUFFER_TOKEN, SECBUFFER_EXTRA = 0, 1, 2, 5
local SECBUFFER_STREAM_TRAILER, SECBUFFER_STREAM_HEADER = 6, 7
local ISC_FLAGS = 0x8 + 0x4 + 0x10 + 0x100 + 0x8000 + 0x4000 -- sequence, replay, confidentiality, allocate,
                                                              -- stream, extended error
local SP_PROT_TLS1_2_CLIENT = 0x800
local SCH_CRED_NO_DEFAULT_CREDS, SCH_CRED_AUTO_CRED_VALIDATION = 0x10, 0x20

local function hex(status)
  return ("0x%08x"):format(bit.band(status, 0xffffffff) % 2 ^ 32)
end

local function descriptor(n)
  local bufs = ffi.new("GC_SecBuffer[?]", n)
  local desc = ffi.new("GC_SecBufferDesc", { 0, n, bufs })
  return desc, bufs
end

local Conn = {}
Conn.__index = Conn

-- Sends all of `data` on the tcp socket, whatever its timeout.
local function sendAll(tcp, data)
  local i = 1
  while i <= #data do
    local last, err, partial = tcp:send(data, i)
    if last then i = last + 1
    elseif err == "timeout" then i = (partial or i - 1) + 1
    else return nil, err end
  end
  return true
end

-- Runs the handshake on a connected tcp socket. Returns a connection, or nil and an error message.
function M.connect(tcp, host, timeout)
  local cred = ffi.new("GC_SecHandle")
  local sc = ffi.new("GC_SCHANNEL_CRED")
  sc.dwVersion = 4
  sc.grbitEnabledProtocols = SP_PROT_TLS1_2_CLIENT
  sc.dwFlags = SCH_CRED_NO_DEFAULT_CREDS + SCH_CRED_AUTO_CRED_VALIDATION
  local status = sspi.AcquireCredentialsHandleA(nil, "Microsoft Unified Security Protocol Provider", 2, nil, sc,
    nil, nil, cred, nil)
  if status ~= SEC_E_OK then return nil, "AcquireCredentialsHandle " .. hex(status) end

  local ctx = ffi.new("GC_SecHandle")
  local attrs = ffi.new("unsigned long[1]")
  local outDesc, outBufs = descriptor(1)
  local function flushToken()
    if outBufs[0].cbBuffer > 0 and outBufs[0].pvBuffer ~= nil then
      local sent, err = sendAll(tcp, ffi.string(outBufs[0].pvBuffer, outBufs[0].cbBuffer))
      sspi.FreeContextBuffer(outBufs[0].pvBuffer)
      outBufs[0].pvBuffer, outBufs[0].cbBuffer = nil, 0
      return sent, err
    end
    return true
  end
  local function fail(msg)
    sspi.DeleteSecurityContext(ctx)
    sspi.FreeCredentialsHandle(cred)
    return nil, msg
  end

  outBufs[0].BufferType = SECBUFFER_TOKEN
  status = sspi.InitializeSecurityContextA(cred, nil, host, ISC_FLAGS, 0, 0, nil, 0, ctx, outDesc, attrs, nil)
  if status ~= SEC_I_CONTINUE_NEEDED then return fail("handshake start " .. hex(status)) end
  local sent, err = flushToken()
  if not sent then return fail("handshake send: " .. tostring(err)) end

  local input = ""
  local deadline = socket.gettime() + (timeout or 10)
  local needData = true
  tcp:settimeout(0.5)
  while true do
    if needData then
      local data, rerr, partial = tcp:receive(16384)
      local chunk = data or partial
      if chunk and #chunk > 0 then input = input .. chunk
      elseif rerr == "closed" then return fail("connection closed during the TLS handshake") end
      if socket.gettime() > deadline then return fail("TLS handshake timed out") end
      if not chunk or #chunk == 0 then goto continue end
    end
    do
      local inDesc, inBufs = descriptor(2)
      local inData = ffi.new("uint8_t[?]", #input)
      ffi.copy(inData, input, #input)
      inBufs[0].BufferType, inBufs[0].cbBuffer, inBufs[0].pvBuffer = SECBUFFER_TOKEN, #input, inData
      inBufs[1].BufferType = SECBUFFER_EMPTY
      outBufs[0].BufferType, outBufs[0].cbBuffer, outBufs[0].pvBuffer = SECBUFFER_TOKEN, 0, nil
      status = sspi.InitializeSecurityContextA(cred, ctx, host, ISC_FLAGS, 0, 0, inDesc, 0, nil, outDesc, attrs, nil)
      if status == SEC_E_INCOMPLETE_MESSAGE then
        needData = true
      else
        sent, err = flushToken()
        if not sent then return fail("handshake send: " .. tostring(err)) end
        if inBufs[1].BufferType == SECBUFFER_EXTRA and inBufs[1].cbBuffer > 0 then
          input = input:sub(#input - inBufs[1].cbBuffer + 1)
          needData = false
        else
          input = ""
          needData = true
        end
        if status == SEC_E_OK then break end
        if status ~= SEC_I_CONTINUE_NEEDED then return fail("TLS handshake failed " .. hex(status)) end
      end
    end
    ::continue::
  end

  local sizes = ffi.new("GC_StreamSizes")
  status = sspi.QueryContextAttributesA(ctx, 4, sizes)
  if status ~= SEC_E_OK then return fail("stream sizes " .. hex(status)) end
  return setmetatable({ tcp = tcp, cred = cred, ctx = ctx, sizes = sizes, encrypted = input, plain = {} }, Conn)
end

function Conn:send(data)
  local sizes = self.sizes
  local i = 1
  while i <= #data do
    local chunk = data:sub(i, i + sizes.cbMaximumMessage - 1)
    local n = #chunk
    local buf = ffi.new("uint8_t[?]", sizes.cbHeader + n + sizes.cbTrailer)
    ffi.copy(buf + sizes.cbHeader, chunk, n)
    local desc, bufs = descriptor(4)
    bufs[0].BufferType, bufs[0].cbBuffer, bufs[0].pvBuffer = SECBUFFER_STREAM_HEADER, sizes.cbHeader, buf
    bufs[1].BufferType, bufs[1].cbBuffer, bufs[1].pvBuffer = SECBUFFER_DATA, n, buf + sizes.cbHeader
    bufs[2].BufferType, bufs[2].cbBuffer, bufs[2].pvBuffer = SECBUFFER_STREAM_TRAILER, sizes.cbTrailer,
      buf + sizes.cbHeader + n
    bufs[3].BufferType = SECBUFFER_EMPTY
    local status = sspi.EncryptMessage(self.ctx, 0, desc, 0)
    if status ~= SEC_E_OK then return nil, "encrypt " .. hex(status) end
    local total = bufs[0].cbBuffer + bufs[1].cbBuffer + bufs[2].cbBuffer
    local sent, err = sendAll(self.tcp, ffi.string(buf, total))
    if not sent then return nil, err end
    i = i + n
  end
  return true
end

-- Like tcp:receive(n) with a timeout: returns decrypted data, or nil and "timeout" / "closed" / an error.
function Conn:receive()
  local data, err, partial = self.tcp:receive(65536)
  local chunk = data or partial
  if chunk and #chunk > 0 then self.encrypted = self.encrypted .. chunk end
  local out = {}
  while #self.encrypted > 0 do
    local enc = self.encrypted
    local buf = ffi.new("uint8_t[?]", #enc)
    ffi.copy(buf, enc, #enc)
    local desc, bufs = descriptor(4)
    bufs[0].BufferType, bufs[0].cbBuffer, bufs[0].pvBuffer = SECBUFFER_DATA, #enc, buf
    for k = 1, 3 do bufs[k].BufferType = SECBUFFER_EMPTY end
    local status = sspi.DecryptMessage(self.ctx, desc, 0, nil)
    if status == SEC_E_INCOMPLETE_MESSAGE then break end
    if status == SEC_I_CONTEXT_EXPIRED then
      self.encrypted = ""
      err = "closed"
      break
    end
    if status ~= SEC_E_OK and status ~= SEC_I_RENEGOTIATE then
      return nil, "decrypt " .. hex(status)
    end
    local extra = ""
    for k = 0, 3 do
      if bufs[k].BufferType == SECBUFFER_DATA and bufs[k].cbBuffer > 0 then
        out[#out + 1] = ffi.string(bufs[k].pvBuffer, bufs[k].cbBuffer)
      elseif bufs[k].BufferType == SECBUFFER_EXTRA and bufs[k].cbBuffer > 0 then
        extra = enc:sub(#enc - bufs[k].cbBuffer + 1)
      end
    end
    self.encrypted = extra
    if status == SEC_I_RENEGOTIATE then break end
  end
  if #out > 0 then return table.concat(out) end
  return nil, err or "timeout"
end

function Conn:settimeout(t) self.tcp:settimeout(t) end

function Conn:close()
  sspi.DeleteSecurityContext(self.ctx)
  sspi.FreeCredentialsHandle(self.cred)
  self.tcp:close()
end

return M
