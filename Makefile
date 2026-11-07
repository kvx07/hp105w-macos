# hp105w-macos — Makefile
# 常用入口，全部不需要 sudo（install/uninstall 除外，它们内部会 sudo）

SHELL := /bin/bash
ROOT  := $(shell pwd)

.PHONY: help build install uninstall app test lint diagnose clean

help:
	@echo "make build      下载并编译 QPDL 编码器、生成 PPD"
	@echo "make install    装成系统打印队列（会要一次管理员密码）"
	@echo "make uninstall  移除队列与过滤器"
	@echo "make app        生成可拖拽的 HP105w-Print.app"
	@echo "make test       跑自检（不需要打印机）"
	@echo "make lint       shellcheck"
	@echo "make diagnose  体检当前打印机与队列"
	@echo "make clean      删除 build/ 与 vendor 二进制"

build:
	@./scripts/build.sh

install:
	@./scripts/install.sh

uninstall:
	@./scripts/uninstall.sh

app:
	@./scripts/make-app.sh

test:
	@./tests/smoke.sh

lint:
	@command -v shellcheck >/dev/null || { echo "需要 shellcheck: brew install shellcheck"; exit 1; }
	@shellcheck -S warning bin/hp105w-print scripts/*.sh tests/smoke.sh

diagnose:
	@./scripts/diagnose.sh

clean:
	@rm -rf build bin/vendor HP105w-Print.app
	@echo "已清理"
