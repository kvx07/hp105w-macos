-- HP105w-Print.app — 拖拽打印小程序（由 scripts/make-app.sh 编译）
on open theFiles
	set homeDir to POSIX path of (path to home folder)
	set candidates to {homeDir & "hp105w-macos/bin/hp105w-print", homeDir & "hp105w/bin/hp105w-print"}
	set exe to ""
	repeat with c in candidates
		try
			do shell script "test -x " & quoted form of (c as text)
			set exe to c as text
			exit repeat
		end try
	end repeat
	if exe is "" then
		display dialog "找不到 hp105w-print。先在本项目目录运行 make build。" buttons {"好"} default button 1
		return
	end if

	set cmd to quoted form of exe & " -q"
	repeat with f in theFiles
		set cmd to cmd & " " & quoted form of (POSIX path of f)
	end repeat

	try
		do shell script cmd
		display notification "已发送到 HP Laser 105w" with title "hp105w"
	on error errMsg
		display dialog "打印失败：" & errMsg buttons {"好"} default button 1
	end try
end open

on run
	display dialog "把 PDF / 文本 / 图片拖到这个 App 上即可打印。" buttons {"好"} default button 1
end run
