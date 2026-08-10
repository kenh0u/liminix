-- different devices have different u-boot prompts.  this cavorting is
-- so we can (fairly) reliably tell when u-boot is ready to
-- accept more input, without depending on the prompt

write("setenv ready REA; setenv ready ${ready}DY\r") msleep(100)

function send_command(s, timeout)
  write(s .. "; echo ${ready}\r\n")
  local ok, matched = expect("READY|BusyBox", timeout)
  if not ok then
    error("timeout after sending ".. s)
  end
  print("got " .. matched)
  if matched:match("BusyBox") then
    return false
  end
  return true
end

function send_script(f)
  for line in f:lines() do
    if not send_command(line) then return end
  end
end

send_command("version")
local f = io.open("result/boot.scr")
send_script(f)
f:close()


-- # This is for use with minicom, but needs you to configure it to
-- # use expect as its "Script program" instead of runscript.  Try
-- # Ctrl+A O -> Filenames and paths -> D

-- fconfigure stderr -buffering  none
-- fconfigure stdout -buffering  none

-- proc waitprompt { } {
--     expect {
--       "BusyBox" { puts stderr  "DONE\r"; exit 0 }
--       "READY" { puts stderr ";;; READY\r"; }
--       timeout { puts stderr ";;; timed out waiting after $line\r" }
--     }
-- }

-- proc sendline { line } {
--      send "$line; echo \$ready \r"
--      sleep 0.1
-- }

-- log_user 0
-- log_file -a -open stderr

-- set f [open "result/boot.scr"]

-- send "setenv ready REA\r"
-- sleep 0.1
-- send "setenv ready \${ready}DY\r"
-- sleep 0.1

-- set timeout 300
-- expect_before timeout abort
-- while {[gets $f line] >= 0} {
--     puts stderr ";;; next line $line\r"
--     puts stderr ";;; waiting for prompt\r"
--     puts stderr ";;; sending\r"
--     sendline $line
--     waitprompt
-- }

-- puts stderr "done\r\n"
-- close $f
