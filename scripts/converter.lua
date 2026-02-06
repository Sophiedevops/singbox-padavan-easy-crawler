-- === ВСТРОЕННЫЕ УТИЛИТЫ ===
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function decodeBase64(data)
    if not data then return "" end
    data = string.gsub(data, '-', '+')
    data = string.gsub(data, '_', '/')
    local mod4 = #data % 4
    if mod4 > 0 then data = data .. string.rep('=', 4 - mod4) end
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

local function urlDecode(s)
    if not s then return "" end
    s = string.gsub(s, '%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
    return s
end

-- === ФУНКЦИИ ПРОВЕРКИ ===

local function safe(s)
    if not s then return "" end
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, '"', '\\"')
    s = string.gsub(s, "[%c]", "")
    s = string.gsub(s, "^%s*(.-)%s*$", "%1")
    return s
end

local function clean(s, idx)
    if not s then s = "Node" end
    s = string.gsub(s, "[^a-zA-Z0-9%-%_]", "")
    if s == "" then s = "Node" end
    return s .. "_" .. idx
end

local function is_valid_method(m)
    if not m then return false end
    m = string.lower(m)
    if m == "aes-128-gcm" then return true end
    if m == "aes-256-gcm" then return true end
    if m == "chacha20-ietf-poly1305" then return true end
    if m == "chacha20-poly1305" then return true end
    if m == "2022-blake3-aes-128-gcm" then return true end
    if m == "2022-blake3-aes-256-gcm" then return true end
    if m == "none" then return true end
    if m == "plain" then return true end
    return false
end

local function parseQ(q)
    local r = {}
    if not q then return r end
    for k, v in string.gmatch(q, "([^&=?]+)=([^&=?]+)") do
        r[k] = urlDecode(v)
    end
    return r
end

local function getJ(s, k)
    local p = '"' .. k .. '"%s*:%s*"(.-)"'
    local v = string.match(s, p)
    if not v then
        p = '"' .. k .. '"%s*:%s*([%w%.%-]+)'
        v = string.match(s, p)
    end
    return v
end

-- === ГЕНЕРАТОРЫ ===

local function mkSS(s, n)
    local u, hp = s:match("^(.-)@(.*)")
    if not u then return nil end
    
    local dec = decodeBase64(u)
    local m, p = dec:match("^(.-):(.*)")
    local h, port = hp:match("^(.-):(%d+)")
    
    if not h or h == "" then return nil end
    if not port or tonumber(port) == 0 then return nil end
    if not m then return nil end
    
    -- ПРОВЕРКА ВАЛИДНОСТИ МЕТОДА
    if not is_valid_method(m) then return nil end
    if m == "chacha20-poly1305" then m = "chacha20-ietf-poly1305" end
    
    return string.format('{ "type": "shadowsocks", "tag": "%s", "server": "%s", "server_port": %s, "method": "%s", "password": "%s" }', safe(n), safe(h), port, safe(m), safe(p))
end

local function mkVless(s, n)
    local u, rest = s:match("^(.-)@(.*)")
    if not u then return nil end
    local h, port, p_str = rest:match("^(.-):(%d+)%?(.*)")
    if not p_str then h, port = rest:match("^(.-):(%d+)"); p_str = "" end
    
    if not h or h == "" then return nil end
    if not port or tonumber(port) == 0 then return nil end
    
    local p = parseQ(p_str)
    local tls = "false"; local sn = ""
    local sec = p["security"]
    if sec == "tls" or sec == "reality" then tls = "true"; sn = p["sni"] or h end
    local tr = ""
    local tt = p["type"]
    if tt == "ws" then
        tr = string.format(', "transport": { "type": "ws", "path": "%s", "headers": { "Host": "%s" } }', safe(p["path"] or "/"), safe(p["host"] or sn))
    elseif tt == "grpc" then
        tr = string.format(', "transport": { "type": "grpc", "service_name": "%s" }', safe(p["serviceName"] or "grpc"))
    end
    return string.format('{ "type": "vless", "tag": "%s", "server": "%s", "server_port": %s, "uuid": "%s", "flow": "%s", "tls": { "enabled": %s, "server_name": "%s", "insecure": true }%s }', safe(n), safe(h), port, safe(u), safe(p["flow"] or ""), tls, safe(sn), tr)
end

local function mkVmess(b64, n)
    local j = decodeBase64(b64)
    if not j or j == "" then return nil end
    local add = getJ(j, "add"); local port = getJ(j, "port")
    local id = getJ(j, "id"); local aid = getJ(j, "aid")
    local net = getJ(j, "net"); local h = getJ(j, "host")
    local path = getJ(j, "path"); local tls = getJ(j, "tls")
    local sni = getJ(j, "sni")
    
    if not add or add == "" then return nil end
    if not port or tonumber(port) == 0 then return nil end
    if not id then return nil end
    
    local tls_en = "false"; local sn = ""
    if tls == "tls" then tls_en = "true"; sn = sni or h or add end
    local tr = ""
    if net == "ws" then
        tr = string.format(', "transport": { "type": "ws", "path": "%s", "headers": { "Host": "%s" } }', safe(path or "/"), safe(h or ""))
    elseif net == "grpc" then
         tr = string.format(', "transport": { "type": "grpc", "service_name": "%s" }', safe(path or "grpc"))
    end
    return string.format('{ "type": "vmess", "tag": "%s", "server": "%s", "server_port": %s, "uuid": "%s", "alter_id": %s, "security": "auto", "tls": { "enabled": %s, "server_name": "%s", "insecure": true }%s }', safe(n), safe(add), port, safe(id), aid or 0, tls_en, safe(sn), tr)
end

-- === MAIN ===
local f = io.open("subs_raw.txt", "r")
if not f then print("0"); os.exit(1) end
local content = f:read("*all")
f:close()

local txt = content
if not (string.find(content, "vmess://") or string.find(content, "vless://") or string.find(content, "ss://")) then
    txt = decodeBase64(content)
end

local nodes = {}
local count = 0

for line in string.gmatch(txt, "[^\r\n]+") do
    line = string.gsub(line, "%s+", "")
    if line ~= "" then
        local rn = "Node"
        local lnk = line
        local hp = string.find(line, "#")
        if hp then
            lnk = string.sub(line, 1, hp - 1)
            rn = string.sub(line, hp + 1)
        end
        
        rn = urlDecode(rn)
        local un = clean(rn, count)
        
        local nd = nil
        if string.find(lnk, "^ss://") then nd = mkSS(string.sub(lnk, 6), un)
        elseif string.find(lnk, "^vless://") then nd = mkVless(string.sub(lnk, 9), un)
        elseif string.find(lnk, "^vmess://") then nd = mkVmess(string.sub(lnk, 9), un) end
        
        if nd then table.insert(nodes, nd); count = count + 1 end
    end
end

local fo = io.open("all_nodes.json", "w")
fo:write("[\n" .. table.concat(nodes, ",\n") .. "\n]")
fo:close()
print(count)
