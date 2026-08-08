local ffi = require("ffi")

ffi.cdef [[
typedef struct HandwrittenCpsCounter {
    int64_t current;
    int64_t limit;
    int64_t total;
} HandwrittenCpsCounter;
 ]]

local Methods = {}

function Methods:loop()
    if self.current < self.limit then
        return self:body()
    end
    return self:done()
end

function Methods:body()
    self.total = self.total + self.current
    self.current = self.current + 1
    return self:loop()
end

function Methods:done()
    return self.total
end

function Methods:run(limit)
    self.current = 0
    self.limit = limit
    self.total = 0
    return self:loop()
end

return ffi.metatype("HandwrittenCpsCounter", { __index = Methods })

