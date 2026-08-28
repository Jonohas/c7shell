------------------
---- GPU KIND ----
------------------

-- Which kind of GPU this session is on. Two decisions depend on it and they are
-- in different files, so the test lives here rather than in either of them:
--
--   conf/environment.lua  hands clients llvmpipe, because Qt cannot render into
--                         the context aquamarine settles for on these
--   conf/autostart.lua    starts hyprpaper only where hyprpaper can work
--
-- vmwgfx is the one confirmed broken here; the other two are listed because
-- they are software or paravirtual to begin with, so there is no hardware path
-- to lose by treating them the same way.
local M = {}

local VIRTUAL_DRIVERS = { "vmwgfx", "vboxvideo", "virtio_gpu" }

-- Four cards is not a limit on the machine, only on how far this looks: a
-- virtual GPU is card0 on every hypervisor that ships one.
function M.virtual()
    for card = 0, 3 do
        local f = io.open(("/sys/class/drm/card%d/device/uevent"):format(card))
        if f then
            local uevent = f:read("*a")
            f:close()
            for _, driver in ipairs(VIRTUAL_DRIVERS) do
                if uevent:match("DRIVER=" .. driver) then return true end
            end
        end
    end
    return false
end

-- hyprpaper draws through hyprtoolkit, which has no software path: it refuses
-- to start without zwp_linux_dmabuf_v1 and commits a dmabuf for every
-- wallpaper. On a virtual GPU aquamarine cannot build a DRM renderer to import
-- that buffer --
--
--     CDRMRenderer(drm): Can't create renderer, no matching devices found
--     drm: initMgpu: no renderer
--     drm: Failed to update renderer state for <output> on applyCommit
--
-- so the compositor drops the connection and hyprtoolkit aborts on the way out
-- ("ASSERTION FAILED! [core] Disconnected from pollfd id 0"). hyprpaper is
-- therefore not merely wallpaper-less on these machines, it is dead: it
-- SIGABRTs on the first `hyprctl hyprpaper wallpaper` and every one after it
-- reaches nothing. LIBGL_ALWAYS_SOFTWARE does not help, because the buffer is
-- allocated on the device the compositor advertises, not by GL.
--
-- The shell has no such trouble -- it renders with llvmpipe (see
-- conf/environment.lua) and its buffers import fine -- so there it draws the
-- wallpaper itself, on the background layer.
function M.wallpaper_backend()
    return M.virtual() and "shell" or "hyprpaper"
end

return M
