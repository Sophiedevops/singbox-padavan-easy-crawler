local M = {}

-- Таблица для Base64
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

function M.decodeBase64(data)
    if not data then return "" end
    -- Fix URL-Safe Base64 (заменяем -_ на +/)
    data = string.gsub(data, '-', '+')
    data = string.gsub(data, '_', '/')
    
    -- Выравнивание (padding)
    local mod4 = #data % 4
    if mod4 > 0 then
        data = data .. string.rep('=', 4 - mod4)
    end

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

function M.urlDecode(s)
    if not s then return "" end
    s = string.gsub(s, '%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
    return s
end

return M
