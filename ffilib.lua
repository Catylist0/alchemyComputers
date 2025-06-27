local ffi = require "ffi"
local sleep, jit_time

local total_sleep_time = 0

if jit.os == "Windows" then
    ffi.cdef [[
    typedef long long LARGE_INTEGER;
    int QueryPerformanceCounter(LARGE_INTEGER *lpPerformanceCount);
    int QueryPerformanceFrequency(LARGE_INTEGER *lpFrequency);
    void Sleep(unsigned long ms);
  ]]

    local freq_ptr = ffi.new("LARGE_INTEGER[1]")
    assert(ffi.C.QueryPerformanceFrequency(freq_ptr) ~= 0, "QueryPerformanceFrequency failed")
    local freq = tonumber(freq_ptr[0])
    local counter_ptr = ffi.new("LARGE_INTEGER[1]")

    jit_time = function()
        ffi.C.QueryPerformanceCounter(counter_ptr)
        return tonumber(counter_ptr[0]) / freq
    end

    sleep = function(sec)
        ffi.C.Sleep(sec * 1000)
        total_sleep_time = total_sleep_time + sec
    end

else
    ffi.cdef [[
    struct timespec { long tv_sec; long tv_nsec; };
    int clock_gettime(int clk_id, struct timespec *tp);
    int nanosleep(const struct timespec *req, struct timespec *rem);
  ]]
    local CLOCK_MONOTONIC = 1
    local ts = ffi.new("struct timespec[1]")

    jit_time = function()
        ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
        return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_nsec) * 1e-9
    end

    sleep = function(sec)
        local s = math.floor(sec)
        ts[0].tv_sec = s
        ts[0].tv_nsec = (sec - s) * 1e9
        ffi.C.nanosleep(ts, nil)
        total_sleep_time = total_sleep_time + sec
    end
end

get_total_sleep_time = function()
    return total_sleep_time
end

_G.SLEEP = sleep
_G.JIT_TIME = jit_time
_G.GET_TOTAL_SLEEP_TIME = get_total_sleep_time