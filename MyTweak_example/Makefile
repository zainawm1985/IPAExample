# ============================================================
#  MyTweak 编译 Makefile
#  目标：产出 arm64 的 MyTweak.dylib，可用于 TrollStore / Sideloadly 注入
#  使用环境：
#    方式A: macOS + Xcode CommandLineTools (原生编译 arm64 dylib)
#    方式B: macOS + Theos (logos语法，传统tweak写法)
#    方式C: 交叉编译 (无Mac可参考文档说明用GitHub Actions)
# ============================================================

# -------- 基本配置 --------
TARGET_NAME   := MyTweak
TARGET_ARCH   := arm64
SRC_FILES     := MyTweak.m
OUT_DIR       := build
DYLIB_NAME    := $(TARGET_NAME).dylib
INSTALL_NAME  := @rpath/$(DYLIB_NAME)

# 依赖：系统Frameworks
FRAMEWORKS    := -framework Foundation -framework UIKit -framework QuartzCore

# 如果需要链接CydiaSubstrate.framework（可选，我们的示例代码里是动态dlsym查找）
# EXTRA_LDFLAGS := -F./vendor -framework CydiaSubstrate

# SDK路径：用 xcrun 自动取，也可以硬编码
SDKROOT       := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
ifeq ($(SDKROOT),)
$(error 找不到iPhoneOS SDK，请先在macOS上安装Xcode CommandLineTools: xcode-select --install)
endif

CC            := xcrun --sdk iphoneos clang
CFLAGS        := -arch $(TARGET_ARCH) -isysroot $(SDKROOT) \
                 -miphoneos-version-min=14.0 -fobjc-arc -fobjc-weak -Os \
                 -Wall -Wno-unused-variable -Wno-unused-function
LDFLAGS       := -arch $(TARGET_ARCH) -isysroot $(SDKROOT) \
                 -dynamiclib -install_name $(INSTALL_NAME) \
                 -compatibility_version 1.0 -current_version 1.0.0 \
                 -miphoneos-version-min=14.0 \
                 -dead_strip $(FRAMEWORKS) $(EXTRA_LDFLAGS)

# ============================================================
.PHONY: all clean sign package sideloadly-package help

all: $(OUT_DIR)/$(DYLIB_NAME)
	@echo ""
	@echo "✅ 编译完成: $(OUT_DIR)/$(DYLIB_NAME)"
	@$(eval SIZE := $(shell stat -f%z $(OUT_DIR)/$(DYLIB_NAME) 2>/dev/null || stat -c%s $(OUT_DIR)/$(DYLIB_NAME) 2>/dev/null || echo "?"))
	@echo "   大小: $(SIZE) 字节"
	@echo ""
	@echo "📝 注入方式："
	@echo "   方式1 - Sideloadly: 将此dylib拖入Sideloadly的dylib注入框，再选IPA"
	@echo "   方式2 - optool手动注入:"
	@echo "      optool install -c load -p @executable_path/Frameworks/$(DYLIB_NAME) -t Payload/TargetApp.app/TargetApp"
	@echo "   方式3 - TrollStore TCI: 改名放到TrollStore的Injection目录 (需TrollStore支持)"
	@echo ""

# -------- 编译 dylib --------
$(OUT_DIR)/$(DYLIB_NAME): $(SRC_FILES) | $(OUT_DIR)
	@echo "🔨 编译: $(SRC_FILES) -> $@"
	$(CC) $(CFLAGS) $(SRC_FILES) $(LDFLAGS) -o $@
	# 可选：strip一下符号减小体积（但调试时留着符号更好）
	# xcrun --sdk iphoneos strip -x $@
	# 检查下产出
	@file $@ || true
	@echo ""
	@echo "🔍 install name:"
	@xcrun --sdk iphoneos otool -D $@ || true
	@echo ""
	@echo "🔍 依赖库:"
	@xcrun --sdk iphoneos otool -L $@ || true

$(OUT_DIR):
	mkdir -p $@

# -------- Adhoc签名 (TrollStore/Sideloadly要求) --------
sign: $(OUT_DIR)/$(DYLIB_NAME)
	@echo "✍️  Ad-Hoc 签名..."
	# 用 - 代表adhoc (entitlements可以加也可以不加，Sideloadly安装时会重签)
	xcrun --sdk iphoneos codesign -f -s - --timestamp=none $(OUT_DIR)/$(DYLIB_NAME)
	@echo "✅ 签名完成"

# -------- 查看签名信息 --------
check: $(OUT_DIR)/$(DYLIB_NAME)
	@echo "🔍 Mach-O 信息:"
	@xcrun --sdk iphoneos otool -hv $@
	@echo ""
	@echo "🔍 签名信息:"
	@xcrun --sdk iphoneos codesign -dvv $@ 2>&1 || true

# -------- 打包一个用于手动注入的zip包 --------
package: all sign
	@echo "📦 打包供注入使用的zip..."
	cp -r vendor/CydiaSubstrate.framework $(OUT_DIR)/ 2>/dev/null || true
	cd $(OUT_DIR) && zip -r ../$(TARGET_NAME)_for_injection.zip .
	@echo "✅ 已产出 $(TARGET_NAME)_for_injection.zip"

# ============================================================
#  纯手工IPA注入演示 (macOS上执行此步骤)
#  用法: make manual-inject IPA=/path/to/Target.ipa
# ============================================================
IPA ?=
manual-inject: all sign
ifeq ($(IPA),)
	$(error 请指定 IPA: make manual-inject IPA=/path/to/TargetApp.ipa)
endif
	@echo "📤 解压IPA到 tmp_unz ..."
	@rm -rf tmp_unz tmp_out
	@mkdir -p tmp_unz tmp_out
	@unzip -q $(IPA) -d tmp_unz
	@APP_DIR=$(shell ls -d tmp_unz/Payload/*.app | head -n1); \
	 APP_NAME=$$(basename $$APP_DIR .app); \
	 echo "📱 App: $$APP_NAME (路径 $$APP_DIR)"; \
	 EXEC=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" $$APP_DIR/Info.plist); \
	 echo "⚙️  可执行文件: $$EXEC"; \
	 mkdir -p $$APP_DIR/Frameworks; \
	 cp $(OUT_DIR)/$(DYLIB_NAME) $$APP_DIR/Frameworks/; \
	 if [ -d vendor/CydiaSubstrate.framework ]; then \
	     cp -R vendor/CydiaSubstrate.framework $$APP_DIR/Frameworks/; \
	 fi; \
	 echo "🪄 插入LC_LOAD_DYLIB命令 (用optool)..."; \
	 (which optool || (echo "未找到optool，尝试brew install alexey-sun/tmp/optool 或手动编译")); \
	 if which optool >/dev/null 2>&1; then \
	     optool install -c load -p "@rpath/$(DYLIB_NAME)" -t $$APP_DIR/$$EXEC || true; \
	 fi; \
	 echo "🪄 插入 fallback @executable_path/Frameworks/ 为 LC_RPATH..."; \
	 if which optool >/dev/null 2>&1; then \
	     optool install -c rpath -p "@executable_path/Frameworks" -t $$APP_DIR/$$EXEC 2>/dev/null || true; \
	 fi; \
	 \
	 echo "✍️  对整个App目录AdHoc签名..."; \
	 (xcrun --sdk iphoneos codesign -f -s - --timestamp=none --deep $$APP_DIR/Frameworks/* 2>/dev/null || true); \
	 xcrun --sdk iphoneos codesign -f -s - --timestamp=none --entitlements /dev/null --deep $$APP_DIR 2>/dev/null || true; \
	 \
	 echo "📦 重打包为 IPA..."; \
	 cd tmp_unz && zip -qr ../tmp_out/$$APP_NAME\_tweaked.ipa Payload/ && echo "✅ 输出: tmp_out/$$APP_NAME\_tweaked.ipa"

# ============================================================
#  清理
# ============================================================
clean:
	rm -rf $(OUT_DIR) tmp_unz tmp_out $(TARGET_NAME)_for_injection.zip

help:
	@echo "可用目标:"
	@echo "  make all              编译dylib"
	@echo "  make sign             AdHoc签名"
	@echo "  make check            查看Mach-O信息和签名"
	@echo "  make clean            清理构建产物"
	@echo "  make package          打包zip"
	@echo "  make manual-inject IPA=/path/to/app.ipa    手动注入到IPA"
