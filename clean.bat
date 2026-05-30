@echo OFF
del /Q *.log
del /Q .serverinfo
del /Q qverify_ui_cmds.tcl
del /Q qverify_cmds.tcl
del /Q questa.ini
del /Q fileList.txt history history.cnt top_dus version
rmdir /S/Q qrun.out
rmdir /S/Q output_lint
rmdir /S/Q .visualizer
rmdir /S/Q .qverify
rmdir /S/Q work
rmdir /S/Q work_db
rmdir /S/Q sessions

