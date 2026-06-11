package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local mem = require("moonlift.mem")
local M = mem.words()

local AudioBufferRecord = { name = "AudioBufferRecord" }

local DawMemory = M.world "DawMemory" {
    M.scope "assets" {
        M.store "audio_buffers" {
            handle = "AudioBufferHandle",
            record = AudioBufferRecord,
            capacity = 16384,
            generation = true,
            publish = "immutable",
        },
    },

    M.scope "audio" {
        M.arena "block" {
            size = "8mb",
            reset = "audio_quantum",
            realtime = true,
            allocation = "preallocated_only",
        },

        M.rule "no_general_alloc",
        M.rule "no_resource_close",
        M.rule "no_handle_discovery",
    },
}

assert(DawMemory.name == "DawMemory")
assert(DawMemory.assets.audio_buffers.kind == "store")
assert(DawMemory.audio.block.kind == "arena")
assert(#DawMemory.audio.rules == 3)

local decls = DawMemory:declarations()
assert(decls[1].kind == "scope" and decls[1].name == "assets")
assert(decls[2].kind == "store" and decls[2].names.input == "BorrowAudioBufferInput")
assert(decls[2].names.output == "BorrowAudioBufferOutput")
assert(decls[2].names.region == "borrow_audio_buffer")

local text = DawMemory:moonlift_declarations()
assert(text:match("struct AudioBufferHandle"), text)
assert(text:match("union BorrowAudioBufferOutput"), text)
assert(text:match("region borrow_audio_buffer"), text)
assert(text:match("struct AudioBlockArenaOwner"), text)
assert(text:match("region reserve_audio_block_arena"), text)
assert(text:match("%-%- rule no_general_alloc"), text)

local staged = DawMemory.assets.audio_buffers:borrow {
    handle = { index = 1, generation = 2 },
    as = "view(f32)",
} {
    borrowed = function(samples)
        return samples {
            function(s)
                return s.len
            end,
        }
    end,
    stale = function() error("unexpected stale") end,
    missing = function() error("unexpected missing") end,
}
assert(staged.kind == "operation")
assert(staged:lowered_names().input == "BorrowAudioBufferInput")

DawMemory.assets.audio_buffers:bind_runtime {
    borrow = function(_, request)
        assert(request.handle.index == 7)
        return "borrowed", mem.borrowed({ ptr = "p", len = 64 }, { name = "samples" })
    end,
}

local got = DawMemory.assets.audio_buffers:borrow {
    handle = { index = 7, generation = 2 },
} {
    borrowed = function(samples)
        return samples {
            function(s)
                assert(s.ptr == "p")
                return s.len
            end,
        }
    end,
    stale = function() error("unexpected stale") end,
    missing = function() error("unexpected missing") end,
}
assert(got == 64)

local b = mem.borrowed({ ptr = "q", len = 3 })
assert(b { function(x) return x.len end } == 3)
local ok = pcall(function()
    b { function(x) return x.len end }
end)
assert(not ok, "borrowed values must not survive their dynamic extent")

print("moonlift mem DSL ok")
