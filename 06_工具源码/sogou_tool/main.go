// 搜狗输入法 离线皮肤/词库管理工具（cangshui）
// 纯 Win32 API 图形界面，无第三方依赖，单文件 exe。
//
// 稳定性要点（修复“打开一段时间自动未响应”）：
//  1. 进入 Win32 消息循环前必须 runtime.LockOSThread()：
//     Go 会把消息循环 goroutine 在 OS 线程间迁移，而 Windows 要求消息泵
//     固定在创建窗口的线程上；缺失会导致窗口随机“(未响应)”。
//  2. 所有磁盘 IO / 子进程调用放到后台 goroutine，结果经 PostMessage 回投 UI。
//  3. 跨线程数据用互斥锁保护的全局变量交接，不经 PostMessage 传堆指针
//     （否则 GC 可能在 UI 线程读取前回收对象 → use-after-free）。
package main

import (
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var (
	user32            = syscall.NewLazyDLL("user32.dll")
	kernel32          = syscall.NewLazyDLL("kernel32.dll")
	comdlg32          = syscall.NewLazyDLL("comdlg32.dll")
	shell32           = syscall.NewLazyDLL("shell32.dll")
	gdi32             = syscall.NewLazyDLL("gdi32.dll")
	pMessageBoxW      = user32.NewProc("MessageBoxW")
	pCreateWindowExW  = user32.NewProc("CreateWindowExW")
	pDefWindowProcW   = user32.NewProc("DefWindowProcW")
	pRegisterClassEx  = user32.NewProc("RegisterClassExW")
	pShowWindow       = user32.NewProc("ShowWindow")
	pUpdateWindow     = user32.NewProc("UpdateWindow")
	pGetMessageW      = user32.NewProc("GetMessageW")
	pTranslateMsg     = user32.NewProc("TranslateMessage")
	pDispatchMsg      = user32.NewProc("DispatchMessageW")
	pPostQuitMessage  = user32.NewProc("PostQuitMessage")
	pPostMessageW     = user32.NewProc("PostMessageW")
	pSendMessageW     = user32.NewProc("SendMessageW")
	pSetWindowTextW   = user32.NewProc("SetWindowTextW")
	pGetModuleHandle  = kernel32.NewProc("GetModuleHandleW")
	pGetOpenFileName  = comdlg32.NewProc("GetOpenFileNameW")
	pShellExecuteW    = shell32.NewProc("ShellExecuteW")
	pGetSystemMetric  = user32.NewProc("GetSystemMetrics")
	pLoadCursorW      = user32.NewProc("LoadCursorW")
	pEnumWindows      = user32.NewProc("EnumWindows")
	pEnumChildWindows = user32.NewProc("EnumChildWindows")
	pGetWindowTextW   = user32.NewProc("GetWindowTextW")
	pGetClassNameW    = user32.NewProc("GetClassNameW")
	pSetForegroundW   = user32.NewProc("SetForegroundWindow")
	pSetWindowPos     = user32.NewProc("SetWindowPos")
	pBringToTop       = user32.NewProc("BringWindowToTop")
	pIsWindowVisible  = user32.NewProc("IsWindowVisible")
	pSendMsgTimeoutW  = user32.NewProc("SendMessageTimeoutW")
	pSetCursor        = user32.NewProc("SetCursor")
	pGetDlgCtrlID     = user32.NewProc("GetDlgCtrlID")
	pGetStockObject   = gdi32.NewProc("GetStockObject")
	pSetTextColor     = gdi32.NewProc("SetTextColor")
	pSetBkMode        = gdi32.NewProc("SetBkMode")
)

func ctrlID(h uintptr) int {
	if h == 0 {
		return 0
	}
	r, _, _ := pGetDlgCtrlID.Call(h)
	return int(int32(r))
}

const (
	BM_CLICK         = 0x00F5
	SMTO_ABORTIFHUNG = 0x0002
)

const (
	HWND_TOPMOST   = ^uintptr(0) // (HWND)-1
	HWND_NOTOPMOST = ^uintptr(1) // (HWND)-2
	SWP_NOSIZE     = 0x0001
	SWP_NOMOVE     = 0x0002
	SWP_SHOWWINDOW = 0x0040
)

const (
	WS_OVERLAPPEDWINDOW = 0x00CF0000
	WS_VISIBLE          = 0x10000000
	WS_CHILD            = 0x40000000
	WS_TABSTOP          = 0x00010000
	WS_VSCROLL          = 0x00200000
	BS_PUSHBUTTON       = 0x00000000
	LBS_NOTIFY          = 0x00000001
	LBS_HASSTRINGS      = 0x00000040
	WS_EX_CLIENTEDGE    = 0x00000200
	SW_SHOW             = 5
	WM_CREATE           = 0x0001
	WM_COMMAND          = 0x0111
	WM_CLOSE            = 0x0010
	WM_DESTROY          = 0x0002
	WM_APP_REFRESH      = 0x8001
	WM_APP_STATUS       = 0x8002
	LB_ADDSTRING        = 0x0180
	LB_RESETCONTENT     = 0x0184
	LB_GETCURSEL        = 0x0188
	LB_GETTEXT          = 0x0189
	LB_GETTEXTLEN       = 0x018A
	OFN_FILEMUSTEXIST   = 0x00001000
	OFN_PATHMUSTEXIST   = 0x00000800
	OFN_EXPLORER        = 0x00080000
	IDC_ARROW           = 32512
	COLOR_WINDOW        = 5
)

// 离线皮肤/词库下载地址 + 作者博客（UI 上均以可点击链接展示，点击调用系统浏览器）
const DOWNLOAD_URL = "https://pinyin.sogou.com/windows/"
const BLOG_URL = "https://cangshui.net"

// 可点击网址标签相关
const (
	SS_NOTIFY         = 0x00000100
	WM_CTLCOLORSTATIC = 0x0138
	WM_SETCURSOR      = 0x0020
	IDC_HAND          = 32649
	TRANSPARENT_BK    = 1
	HOLLOW_BRUSH      = 5
	COLOR_LINK        = 0x00CC6600 // COLORREF 0x00BBGGRR -> 蓝色链接
	COLOR_BLOG        = 0x000000CC // COLORREF 0x00BBGGRR -> 红色（作者博客）
)

type WNDCLASSEXW struct {
	cbSize        uint32
	style         uint32
	lpfnWndProc   uintptr
	cbClsExtra    int32
	cbWndExtra    int32
	hInstance     uintptr
	hIcon         uintptr
	hCursor       uintptr
	hbrBackground uintptr
	lpszMenuName  *uint16
	lpszClassName *uint16
	hIconSm       uintptr
}

type MSG struct {
	hwnd    uintptr
	message uint32
	wParam  uintptr
	lParam  uintptr
	time    uint32
	pt      struct{ x, y int32 }
}

type OPENFILENAMEW struct {
	lStructSize       uint32
	hwndOwner         uintptr
	hInstance         uintptr
	lpstrFilter       *uint16
	lpstrCustomFilter *uint16
	nMaxCustFilter    uint32
	nFilterIndex      uint32
	lpstrFile         *uint16
	nMaxFile          uint32
	lpstrFileTitle    *uint16
	nMaxFileTitle     uint32
	lpstrInitialDir   *uint16
	lpstrTitle        *uint16
	Flags             uint32
	nFileOffset       uint16
	nFileExtension    uint16
	lpstrDefExt       *uint16
	lCustData         uintptr
	lpfnHook          uintptr
	lpTemplateName    *uint16
	pvReserved        uintptr
	dwReserved        uint32
	FlagsEx           uint32
}

var (
	hSkinList uintptr
	hDictList uintptr
	hStatus   uintptr
	hMain     uintptr
)

const INSTALL_DIR = `C:\Program Files (x86)\SogouInput\16.8.0.4914`
const SGTOOL = INSTALL_DIR + `\SGTool.exe`

func utf16(s string) *uint16 {
	p, _ := syscall.UTF16PtrFromString(s)
	return p
}

func msgbox(title, text string, flags uint32) {
	t := utf16(title)
	x := utf16(text)
	pMessageBoxW.Call(hMain, uintptr(unsafe.Pointer(x)), uintptr(unsafe.Pointer(t)), uintptr(flags))
	runtime.KeepAlive(t)
	runtime.KeepAlive(x)
}

func msgboxYesNo(text string) bool {
	t := utf16("确认")
	x := utf16(text)
	r, _, _ := pMessageBoxW.Call(hMain, uintptr(unsafe.Pointer(x)), uintptr(unsafe.Pointer(t)), 0x04|0x20)
	runtime.KeepAlive(t)
	runtime.KeepAlive(x)
	return int32(r) == 6
}

func localLowDir() string {
	return filepath.Join(os.Getenv("USERPROFILE"), "AppData", "LocalLow", "SogouPY")
}
func allSkinDir() string { return filepath.Join(localLowDir(), "AllSkin") }
func scdUserDir() string { return filepath.Join(localLowDir(), "scd") }
func scdProgDir() string { return filepath.Join(INSTALL_DIR, "scd") }

// 工具自己的持久化目录。它与 SogouPY 分开保存，安装/卸载搜狗或输入法
// 清理本地皮肤缓存时不会碰到这里，可作为导入资产的恢复来源。
func toolDataDir() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base = filepath.Join(os.Getenv("USERPROFILE"), "AppData", "Local")
	}
	return filepath.Join(base, "Sogou16-crack")
}
func skinBackupDir() string { return filepath.Join(toolDataDir(), "Backup", "Skins") }
func dictBackupDir() string { return filepath.Join(toolDataDir(), "Backup", "Dictionaries") }
func toolLogPath() string   { return filepath.Join(toolDataDir(), "logs", "tool.log") }

var logMu sync.Mutex

func logf(format string, args ...any) {
	logMu.Lock()
	defer logMu.Unlock()
	_ = os.MkdirAll(filepath.Dir(toolLogPath()), 0755)
	f, err := os.OpenFile(toolLogPath(), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = fmt.Fprintf(f, "%s  %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, args...))
}

// runSGTool 异步启动 SGTool（GUI 程序，不能同步等待）
func runSGTool(args ...string) error {
	cmd := exec.Command(SGTOOL, args...)
	cmd.Dir = INSTALL_DIR
	if err := cmd.Start(); err != nil {
		return err
	}
	go cmd.Wait()
	return nil
}

// runSGToolWait 同步等待 SGTool 命令结束（用于 scdreg 这类快速命令，需拿退出码）
func runSGToolWait(args ...string) error {
	cmd := exec.Command(SGTOOL, args...)
	cmd.Dir = INSTALL_DIR
	return cmd.Run()
}

type refreshMsg struct{ skins, dicts []string }

var (
	ipcMu          sync.Mutex
	pendingRefresh *refreshMsg
	pendingStatus  string
)

func postRefresh(skins, dicts []string) {
	ipcMu.Lock()
	pendingRefresh = &refreshMsg{skins: skins, dicts: dicts}
	ipcMu.Unlock()
	pPostMessageW.Call(hMain, WM_APP_REFRESH, 0, 0)
}

func postStatus(s string) {
	ipcMu.Lock()
	pendingStatus = s
	ipcMu.Unlock()
	pPostMessageW.Call(hMain, WM_APP_STATUS, 0, 0)
}

// scanLists 后台线程扫描磁盘并投递刷新消息
func scanLists() {
	skins := []string{}
	dicts := []string{}
	seen := map[string]bool{}
	if ents, err := os.ReadDir(allSkinDir()); err == nil {
		for _, e := range ents {
			if !e.IsDir() && strings.EqualFold(filepath.Ext(e.Name()), ".ssf") {
				skins = append(skins, strings.TrimSuffix(e.Name(), filepath.Ext(e.Name())))
			}
		}
	}
	for _, dir := range []string{scdUserDir(), scdProgDir()} {
		if ents, err := os.ReadDir(dir); err == nil {
			for _, e := range ents {
				if !e.IsDir() && strings.EqualFold(filepath.Ext(e.Name()), ".scel") {
					if !seen[e.Name()] {
						seen[e.Name()] = true
						dicts = append(dicts, e.Name())
					}
				}
			}
		}
	}
	sort.Strings(skins)
	sort.Strings(dicts)
	postRefresh(skins, dicts)
}

func samePath(a, b string) bool {
	aa, errA := filepath.Abs(a)
	bb, errB := filepath.Abs(b)
	if errA != nil || errB != nil {
		return strings.EqualFold(filepath.Clean(a), filepath.Clean(b))
	}
	return strings.EqualFold(filepath.Clean(aa), filepath.Clean(bb))
}

func fileDigest(path string) (string, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", 0, err
	}
	defer f.Close()
	h := sha256.New()
	n, err := io.Copy(h, f)
	if err != nil {
		return "", 0, err
	}
	return fmt.Sprintf("%x", h.Sum(nil)), n, nil
}

// copyFileVerified 复制文件并核对目标大小，避免出现 UI 显示成功、实际
// 只留下 0 字节或部分文件的假成功。
func copyFileVerified(src, dst string) (string, int64, error) {
	if samePath(src, dst) {
		return fileDigest(dst)
	}

	in, err := os.Open(src)
	if err != nil {
		return "", 0, err
	}
	defer in.Close()
	st, err := in.Stat()
	if err != nil {
		return "", 0, err
	}
	if st.IsDir() {
		return "", 0, fmt.Errorf("源路径是目录，不是文件")
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return "", 0, err
	}

	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
	if err != nil {
		return "", 0, err
	}
	h := sha256.New()
	n, copyErr := io.Copy(io.MultiWriter(out, h), in)
	syncErr := out.Sync()
	closeErr := out.Close()
	if copyErr != nil {
		return "", 0, copyErr
	}
	if syncErr != nil {
		return "", 0, syncErr
	}
	if closeErr != nil {
		return "", 0, closeErr
	}
	if n != st.Size() {
		return "", 0, fmt.Errorf("复制不完整：源 %d 字节，目标 %d 字节", st.Size(), n)
	}
	dstInfo, err := os.Stat(dst)
	if err != nil {
		return "", 0, err
	}
	if dstInfo.Size() != st.Size() {
		return "", 0, fmt.Errorf("目标大小校验失败：期望 %d，实际 %d", st.Size(), dstInfo.Size())
	}
	return fmt.Sprintf("%x", h.Sum(nil)), n, nil
}

// backupFileIfMissing 用于启动时给已有资产建立首份备份，不覆盖旧备份。
func backupFileIfMissing(src, dstDir, dstName string) (string, error) {
	dst := filepath.Join(dstDir, dstName)
	if st, err := os.Stat(dst); err == nil && st.Size() > 0 {
		return dst, nil
	}
	hash, size, err := copyFileVerified(src, dst)
	if err != nil {
		return "", err
	}
	logf("backup created: src=%s dst=%s bytes=%d sha256=%s", src, dst, size, hash)
	return dst, nil
}

// ensureBackupFile 用于成功安装/卸载前刷新备份，让备份跟当前资产保持一致。
func ensureBackupFile(src, dstDir, dstName string) (string, error) {
	dst := filepath.Join(dstDir, dstName)
	hash, size, err := copyFileVerified(src, dst)
	if err != nil {
		return "", err
	}
	logf("backup refreshed: src=%s dst=%s bytes=%d sha256=%s", src, dst, size, hash)
	return dst, nil
}

func seedBackupFiles() {
	if err := os.MkdirAll(skinBackupDir(), 0755); err != nil {
		logf("seed backup: create skin backup dir failed: %v", err)
		return
	}
	if err := os.MkdirAll(dictBackupDir(), 0755); err != nil {
		logf("seed backup: create dict backup dir failed: %v", err)
		return
	}

	for _, e := range mustReadDir(allSkinDir()) {
		if e.IsDir() || !strings.EqualFold(filepath.Ext(e.Name()), ".ssf") {
			continue
		}
		src := filepath.Join(allSkinDir(), e.Name())
		if _, err := backupFileIfMissing(src, skinBackupDir(), e.Name()); err != nil {
			logf("seed skin backup failed: %s: %v", src, err)
		}
	}
	for _, dir := range []string{scdUserDir()} {
		for _, e := range mustReadDir(dir) {
			if e.IsDir() || !strings.EqualFold(filepath.Ext(e.Name()), ".scel") {
				continue
			}
			src := filepath.Join(dir, e.Name())
			if _, err := backupFileIfMissing(src, dictBackupDir(), e.Name()); err != nil {
				logf("seed dict backup failed: %s: %v", src, err)
			}
		}
	}
}

func mustReadDir(dir string) []os.DirEntry {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	return entries
}

func findMatchingFile(dirs []string, src, ext string) string {
	srcHash, srcSize, err := fileDigest(src)
	if err != nil {
		return ""
	}
	for _, dir := range dirs {
		for _, e := range mustReadDir(dir) {
			if e.IsDir() || !strings.EqualFold(filepath.Ext(e.Name()), ext) {
				continue
			}
			p := filepath.Join(dir, e.Name())
			st, err := e.Info()
			if err != nil || st.Size() != srcSize {
				continue
			}
			hash, _, err := fileDigest(p)
			if err == nil && strings.EqualFold(hash, srcHash) {
				return p
			}
		}
	}
	return ""
}

func skinRegistered(name string) bool {
	b, err := os.ReadFile(filepath.Join(localLowDir(), "SkinRecent.ini"))
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "name=") && strings.TrimPrefix(line, "name=") == name {
			return true
		}
	}
	return false
}

func waitForSkinRegistered(name string, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if skinRegistered(name) {
			return true
		}
		time.Sleep(250 * time.Millisecond)
	}
	return skinRegistered(name)
}

func shouldRestore(path string) bool {
	st, err := os.Stat(path)
	return os.IsNotExist(err) || (err == nil && st.Size() == 0)
}

func restoreAssetsFromBackup() {
	skins, dicts := 0, 0
	if err := os.MkdirAll(allSkinDir(), 0755); err == nil {
		for _, e := range mustReadDir(skinBackupDir()) {
			if e.IsDir() || !strings.EqualFold(filepath.Ext(e.Name()), ".ssf") {
				continue
			}
			src := filepath.Join(skinBackupDir(), e.Name())
			dst := filepath.Join(allSkinDir(), e.Name())
			if !shouldRestore(dst) {
				continue
			}
			if _, _, err := copyFileVerified(src, dst); err != nil {
				logf("restore skin failed: src=%s dst=%s: %v", src, dst, err)
			} else {
				skins++
				logf("restore skin ok: src=%s dst=%s", src, dst)
			}
		}
	}
	if err := os.MkdirAll(scdUserDir(), 0755); err == nil {
		for _, e := range mustReadDir(dictBackupDir()) {
			if e.IsDir() || !strings.EqualFold(filepath.Ext(e.Name()), ".scel") {
				continue
			}
			src := filepath.Join(dictBackupDir(), e.Name())
			dst := filepath.Join(scdUserDir(), e.Name())
			if !shouldRestore(dst) {
				continue
			}
			if _, _, err := copyFileVerified(src, dst); err != nil {
				logf("restore dict failed: src=%s dst=%s: %v", src, dst, err)
			} else {
				dicts++
				logf("restore dict ok: src=%s dst=%s", src, dst)
			}
		}
	}
	if dicts > 0 {
		_ = runSGToolWait("--appid=scdreg", "-update")
	}
	logf("restore finished: skins=%d dicts=%d", skins, dicts)
	postStatus(fmt.Sprintf("已从备份恢复：皮肤 %d 个，词库 %d 个", skins, dicts))
	scanLists()
}

func listSel(h uintptr) string {
	r1, _, _ := pSendMessageW.Call(h, LB_GETCURSEL, 0, 0)
	i := int(int32(r1))
	if i < 0 {
		return ""
	}
	r2, _, _ := pSendMessageW.Call(h, LB_GETTEXTLEN, uintptr(i), 0)
	n := int(int32(r2))
	if n <= 0 {
		return ""
	}
	buf := make([]uint16, n+1)
	pSendMessageW.Call(h, LB_GETTEXT, uintptr(i), uintptr(unsafe.Pointer(&buf[0])))
	return syscall.UTF16ToString(buf)
}

func fillList(h uintptr, items []string) {
	pSendMessageW.Call(h, LB_RESETCONTENT, 0, 0)
	for _, s := range items {
		p := utf16(s)
		pSendMessageW.Call(h, LB_ADDSTRING, 0, uintptr(unsafe.Pointer(p)))
		runtime.KeepAlive(p)
	}
}

func openFile(filter, title, defExt string) string {
	buf := make([]uint16, 4096)
	f := utf16(filter)
	t := utf16(title)
	d := utf16(defExt)
	ofn := OPENFILENAMEW{
		lpstrFilter: f,
		lpstrFile:   &buf[0],
		nMaxFile:    uint32(len(buf)),
		lpstrTitle:  t,
		lpstrDefExt: d,
		Flags:       OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_EXPLORER,
	}
	ofn.lStructSize = uint32(unsafe.Sizeof(ofn))
	ofn.hwndOwner = hMain
	r, _, _ := pGetOpenFileName.Call(uintptr(unsafe.Pointer(&ofn)))
	runtime.KeepAlive(f)
	runtime.KeepAlive(t)
	runtime.KeepAlive(d)
	runtime.KeepAlive(buf)
	if r == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf)
}

func openFolder(p string) {
	os.MkdirAll(p, 0755)
	verb := utf16("open")
	pp := utf16(p)
	pShellExecuteW.Call(hMain, uintptr(unsafe.Pointer(verb)), uintptr(unsafe.Pointer(pp)), 0, 0, SW_SHOW)
	runtime.KeepAlive(verb)
	runtime.KeepAlive(pp)
}

func openURL(u string) {
	verb := utf16("open")
	uu := utf16(u)
	pShellExecuteW.Call(hMain, uintptr(unsafe.Pointer(verb)), uintptr(unsafe.Pointer(uu)), 0, 0, SW_SHOW)
	runtime.KeepAlive(verb)
	runtime.KeepAlive(uu)
}

func winText(h uintptr) string {
	buf := make([]uint16, 512)
	n, _, _ := pGetWindowTextW.Call(h, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	runtime.KeepAlive(buf)
	if n == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf[:n])
}

func winClass(h uintptr) string {
	buf := make([]uint16, 256)
	n, _, _ := pGetClassNameW.Call(h, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	runtime.KeepAlive(buf)
	if n == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf[:n])
}

// 注意：syscall.NewCallback 每次调用都会占用一个不可回收的回调槽。
// watchdog 每 300ms 轮询一次，因此回调必须在包初始化时【只创建一次】，
// 否则会持续泄漏（表现为工具内存不断上涨）。
var (
	skinDlgFound   uintptr
	skinDlgClicked bool
)

func cbFindSkinDlg(hwnd, lparam uintptr) uintptr {
	if skinDlgFound != 0 {
		return 0
	}
	vis, _, _ := pIsWindowVisible.Call(hwnd)
	if vis == 0 {
		return 1
	}
	t := winText(hwnd)
	if strings.Contains(t, "安装皮肤") || strings.Contains(t, "皮肤安装") ||
		strings.Contains(t, "确定要安装") {
		skinDlgFound = hwnd
		return 0
	}
	return 1
}

var procFindSkinDlg = syscall.NewCallback(cbFindSkinDlg)

func cbClickYes(child, lparam uintptr) uintptr {
	if skinDlgClicked {
		return 0
	}
	if strings.EqualFold(winClass(child), "Button") {
		if t := winText(child); strings.Contains(t, "确定") {
			var res uintptr
			pSendMsgTimeoutW.Call(child, BM_CLICK, 0, 0, SMTO_ABORTIFHUNG, 800,
				uintptr(unsafe.Pointer(&res)))
			skinDlgClicked = true
			return 0
		}
	}
	return 1
}

var procClickYes = syscall.NewCallback(cbClickYes)

// autoConfirmSkinDialog 找到搜狗弹出的“安装皮肤”确认框并自动点“确定”。
// 这样即使用户没注意到弹窗（它常被主窗口挡住），皮肤安装/切换也能完成。
func autoConfirmSkinDialog() bool {
	skinDlgFound = 0
	skinDlgClicked = false
	pEnumWindows.Call(procFindSkinDlg, 0)
	if skinDlgFound == 0 {
		return false
	}
	// 先提到最前（用户可见），再点“确定”
	pSetWindowPos.Call(skinDlgFound, HWND_TOPMOST, 0, 0, 0, 0,
		SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW)
	pSetWindowPos.Call(skinDlgFound, HWND_NOTOPMOST, 0, 0, 0, 0,
		SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW)
	pBringToTop.Call(skinDlgFound)
	pSetForegroundW.Call(skinDlgFound)
	pEnumChildWindows.Call(skinDlgFound, procClickYes, 0)
	return skinDlgClicked
}

// watchdogSkinConfirm 后台轮询若干秒，自动确认稍后出现的皮肤安装弹窗。
func watchdogSkinConfirm(d time.Duration) {
	deadline := time.Now().Add(d)
	for time.Now().Before(deadline) {
		autoConfirmSkinDialog()
		time.Sleep(300 * time.Millisecond)
	}
}

func setStatusUI(s string) {
	p := utf16(s)
	pSetWindowTextW.Call(hStatus, uintptr(unsafe.Pointer(p)))
	runtime.KeepAlive(p)
}

func main() {
	// Win32 消息循环必须固定在一个 OS 线程上（详见文件头说明）
	runtime.LockOSThread()

	if _, err := os.Stat(SGTOOL); err != nil {
		t := utf16("错误")
		x := utf16("未找到搜狗输入法安装目录：\n" + INSTALL_DIR + "\n\n请先安装搜狗输入法16.8断网绿化版。")
		pMessageBoxW.Call(0, uintptr(unsafe.Pointer(x)), uintptr(unsafe.Pointer(t)), 0x10)
		runtime.KeepAlive(t)
		runtime.KeepAlive(x)
		return
	}
	runUI()
}

func runUI() {
	hInst, _, _ := pGetModuleHandle.Call(0)
	className := utf16("SogouToolWnd")
	cursor, _, _ := pLoadCursorW.Call(0, IDC_ARROW)
	wc := WNDCLASSEXW{
		cbSize:        uint32(unsafe.Sizeof(WNDCLASSEXW{})),
		lpfnWndProc:   syscall.NewCallback(wndProc),
		hInstance:     hInst,
		hCursor:       cursor,
		hbrBackground: COLOR_WINDOW + 1,
		lpszClassName: className,
	}
	pRegisterClassEx.Call(uintptr(unsafe.Pointer(&wc)))
	sw, _, _ := pGetSystemMetric.Call(0)
	sh, _, _ := pGetSystemMetric.Call(1)
	w, h := 620, 600
	x := (int(int32(sw)) - w) / 2
	y := (int(int32(sh)) - h) / 2
	title := utf16("搜狗输入法 - 离线皮肤/词库管理工具")
	pCreateWindowExW.Call(0, uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		WS_OVERLAPPEDWINDOW, uintptr(x), uintptr(y), uintptr(w), uintptr(h),
		0, 0, hInst, 0)
	runtime.KeepAlive(title)
	runtime.KeepAlive(className)
	pShowWindow.Call(hMain, SW_SHOW)
	pUpdateWindow.Call(hMain)

	go func() {
		seedBackupFiles()
		scanLists()
	}()

	var msg MSG
	for {
		r, _, _ := pGetMessageW.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if int32(r) == -1 {
			time.Sleep(10 * time.Millisecond)
			continue
		}
		if int32(r) == 0 {
			break
		}
		pTranslateMsg.Call(uintptr(unsafe.Pointer(&msg)))
		pDispatchMsg.Call(uintptr(unsafe.Pointer(&msg)))
	}
}

func createChildren(hwnd uintptr) {
	hInst, _, _ := pGetModuleHandle.Call(0)
	btn := func(text string, id int, x, y, w, h int) {
		cls := utf16("BUTTON")
		tp := utf16(text)
		pCreateWindowExW.Call(0, uintptr(unsafe.Pointer(cls)),
			uintptr(unsafe.Pointer(tp)),
			WS_CHILD|WS_VISIBLE|BS_PUSHBUTTON|WS_TABSTOP,
			uintptr(x), uintptr(y), uintptr(w), uintptr(h),
			hwnd, uintptr(id), hInst, 0)
		runtime.KeepAlive(cls)
		runtime.KeepAlive(tp)
	}
	label := func(text string, x, y, w, h int) uintptr {
		cls := utf16("STATIC")
		tp := utf16(text)
		hb, _, _ := pCreateWindowExW.Call(0, uintptr(unsafe.Pointer(cls)),
			uintptr(unsafe.Pointer(tp)),
			WS_CHILD|WS_VISIBLE, uintptr(x), uintptr(y), uintptr(w), uintptr(h),
			hwnd, 0, hInst, 0)
		runtime.KeepAlive(cls)
		runtime.KeepAlive(tp)
		return hb
	}
	// 可点击链接标签：STATIC + SS_NOTIFY，点击时向父窗口发 WM_COMMAND(STN_CLICKED)
	linkLabel := func(text string, id, x, y, w, h int) uintptr {
		cls := utf16("STATIC")
		tp := utf16(text)
		hb, _, _ := pCreateWindowExW.Call(0, uintptr(unsafe.Pointer(cls)),
			uintptr(unsafe.Pointer(tp)),
			WS_CHILD|WS_VISIBLE|SS_NOTIFY, uintptr(x), uintptr(y), uintptr(w), uintptr(h),
			hwnd, uintptr(id), hInst, 0)
		runtime.KeepAlive(cls)
		runtime.KeepAlive(tp)
		return hb
	}
	lst := func(x, y, w, h int) uintptr {
		cls := utf16("LISTBOX")
		hb, _, _ := pCreateWindowExW.Call(WS_EX_CLIENTEDGE, uintptr(unsafe.Pointer(cls)),
			0, WS_CHILD|WS_VISIBLE|LBS_NOTIFY|LBS_HASSTRINGS|WS_VSCROLL,
			uintptr(x), uintptr(y), uintptr(w), uintptr(h),
			hwnd, 0, hInst, 0)
		runtime.KeepAlive(cls)
		return hb
	}
	label("皮肤管理", 20, 12, 200, 20)
	hSkinList = lst(20, 36, 400, 150)
	btn("安装皮肤(.ssf)", 1001, 435, 36, 140, 28)
	btn("切换选中皮肤", 1002, 435, 72, 140, 28)
	btn("卸载选中皮肤", 1003, 435, 108, 140, 28)

	label("词库管理（细胞词库 .scel）", 20, 196, 300, 20)
	hDictList = lst(20, 220, 400, 150)
	btn("安装词库(.scel)", 2001, 435, 220, 140, 28)
	btn("卸载选中词库", 2002, 435, 256, 140, 28)
	btn("从备份恢复", 3008, 435, 292, 140, 28)

	btn("刷新列表", 3001, 20, 384, 110, 28)
	btn("打开皮肤目录", 3002, 140, 384, 110, 28)
	btn("打开词库目录", 3003, 260, 384, 110, 28)
	btn("退出", 3004, 435, 384, 140, 28)

	label("离线皮肤/词库下载地址（下载 .ssf / .scel 后用本工具导入）：", 20, 414, 430, 18)
	linkLabel(DOWNLOAD_URL, 4001, 20, 432, 430, 18)
	label("作者博客：", 20, 454, 70, 18)
	linkLabel(BLOG_URL, 4002, 20, 472, 430, 18)

	btn("打开下载页", 3005, 460, 416, 140, 28)
	btn("访问作者博客", 3007, 460, 450, 140, 28)
	btn("使用说明", 3006, 460, 484, 140, 28)

	cls := utf16("STATIC")
	sp := utf16("就绪")
	hStatus, _, _ = pCreateWindowExW.Call(0, uintptr(unsafe.Pointer(cls)),
		uintptr(unsafe.Pointer(sp)),
		WS_CHILD|WS_VISIBLE, 20, 524, 580, 20, hwnd, 0, hInst, 0)
	runtime.KeepAlive(cls)
	runtime.KeepAlive(sp)
}

const helpText = `使用说明

【皮肤】
  安装：点“安装皮肤(.ssf)”，选择本地 .ssf 文件；
        若弹出“确定要安装皮肤”，点“确定”。
  切换：在列表选中皮肤后点“切换选中皮肤”，立即生效。
  卸载：选中后点“卸载选中皮肤”。

【词库（细胞词库）】
  安装：点“安装词库(.scel)”，选择本地 .scel 文件；
        导入后会自动重建索引。若打不出新词，请重启一下输入法
        （Ctrl+空格 切一下中/英，或注销重新登录）再试。
  卸载：选中后点“卸载选中词库”。

【防丢失备份】
  工具会自动把皮肤和词库备份到：
  %LOCALAPPDATA%\Sogou16-crack\Backup
  如果重启后列表中的资产缺失，点“从备份恢复”。
  详细操作日志：
  %LOCALAPPDATA%\Sogou16-crack\logs\tool.log

【文件从哪来】
  断网环境无法用“皮肤/词库商城”，请先到官网页面下载
  .ssf（皮肤）/ .scel（细胞词库）文件，再用本工具导入：

  搜狗官网皮肤/词库页：https://pinyin.sogou.com/windows/
  作者博客：           https://cangshui.net

  皮肤文件(.ssf)本质是 zip；词库文件(.scel)为搜狗细胞词库格式。

【关于】
  本工具随“搜狗输入法 16.8 断网绿化版（cangshui 版）”分发。
  作者博客：https://cangshui.net`

func wndProc(hwnd uintptr, msg uint32, wparam, lparam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		hMain = hwnd
		createChildren(hwnd)
		return 0

	case WM_APP_REFRESH:
		ipcMu.Lock()
		m := pendingRefresh
		pendingRefresh = nil
		ipcMu.Unlock()
		if m != nil {
			fillList(hSkinList, m.skins)
			fillList(hDictList, m.dicts)
			setStatusUI("列表已刷新（皮肤 " + strconv.Itoa(len(m.skins)) + " 个 · 词库 " + strconv.Itoa(len(m.dicts)) + " 个）")
		}
		return 0

	case WM_APP_STATUS:
		ipcMu.Lock()
		s := pendingStatus
		ipcMu.Unlock()
		if s != "" {
			setStatusUI(s)
		}
		return 0

	case WM_COMMAND:
		id := int(wparam & 0xffff)
		switch id {
		case 1001: // 安装皮肤
			f := openFile("搜狗皮肤文件 (*.ssf)\x00*.ssf\x00所有文件 (*.*)\x00*.*\x00\x00", "选择要安装的皮肤文件 (.ssf)", "ssf")
			if f == "" {
				return 0
			}
			base := filepath.Base(f)
			if !strings.EqualFold(filepath.Ext(base), ".ssf") {
				msgbox("提示", "请选择 .ssf 皮肤文件。", 0x40)
				return 0
			}
			name := strings.TrimSuffix(base, filepath.Ext(base))
			postStatus("正在安装皮肤：" + base + " ...")
			go func() {
				if err := os.MkdirAll(allSkinDir(), 0755); err != nil {
					logf("install skin: create dir failed: %v", err)
					postStatus("安装失败：无法创建皮肤目录")
					return
				}
				dest := filepath.Join(allSkinDir(), base)
				hash, size, err := copyFileVerified(f, dest)
				if err != nil {
					logf("install skin: copy failed: src=%s dst=%s: %v", f, dest, err)
					postStatus("安装失败：皮肤文件未能写入 AllSkin")
					return
				}
				logf("install skin: file verified: src=%s dst=%s bytes=%d sha256=%s", f, dest, size, hash)
				if _, err := ensureBackupFile(dest, skinBackupDir(), base); err != nil {
					logf("install skin: backup failed: %s: %v", dest, err)
				}

				// skinreg -install 会弹“确定要安装皮肤”确认框（官方行为，无法静默）
				// 必须传 AllSkin 内的持久路径，不能传用户选择的临时/下载路径。
				go watchdogSkinConfirm(25 * time.Second)
				if err := runSGTool("-line", "0", "-border", "--appid=skinreg", "-install", dest); err != nil {
					logf("install skin: start SGTool failed: %v", err)
					postStatus("皮肤文件已保存，但无法启动 SGTool 注册")
					scanLists()
					return
				}
				registered := waitForSkinRegistered(name, 12*time.Second)
				if registered {
					logf("install skin: registration confirmed: name=%s dest=%s", name, dest)
					postStatus("已安装并应用皮肤：" + name)
				} else {
					logf("install skin: registration not confirmed: name=%s dest=%s", name, dest)
					postStatus("皮肤文件已保存，但注册未确认；请稍后点“切换选中皮肤”")
				}
				scanLists()
			}()

		case 1002: // 切换皮肤
			name := listSel(hSkinList)
			if name == "" {
				msgbox("提示", "请先在列表中选择一个皮肤。", 0x40)
				return 0
			}
			postStatus("正在切换皮肤：" + name + " ...")
			go func() {
				ssf := filepath.Join(allSkinDir(), name+".ssf")
				if _, err := os.Stat(ssf); err != nil {
					logf("switch skin: missing file: %s: %v", ssf, err)
					postStatus("切换失败：皮肤文件不存在")
					return
				}
				if _, err := backupFileIfMissing(ssf, skinBackupDir(), name+".ssf"); err != nil {
					logf("switch skin: backup failed: %s: %v", ssf, err)
				}
				// 经实测：`skinRenderUpdate -skinname=` 单独调用不会真正切换
				// （SkinRecent.ini 不更新）。而 `skinreg -install <已装皮肤.ssf>`
				// 会把该皮肤置为当前使用（写 lastuse/usecnt）——这正是官方
				// “使用皮肤”的效果。故切换 = 对已装皮肤重新执行 install。
				// 关键：把“确定要安装皮肤”确认窗提到最前（否则被主窗口挡住点不到）
				// 放后台轮询，不阻塞后续步骤
				go watchdogSkinConfirm(25 * time.Second)
				if err := runSGTool("-line", "0", "-border", "--appid=skinreg", "-install", ssf); err != nil {
					logf("switch skin: start SGTool failed: %v", err)
					postStatus("切换失败：无法启动 SGTool")
					return
				}
				time.Sleep(1200 * time.Millisecond)
				// 再触发一次渲染刷新
				_ = runSGToolWait("-line", "0", "-border", "--appid=skinRenderUpdate", "-skinname="+name)
				logf("switch skin: requested: name=%s file=%s", name, ssf)
				postStatus("已切换皮肤：" + name + "（确认框已自动点“确定”）")
			}()

		case 1003: // 卸载皮肤
			name := listSel(hSkinList)
			if name == "" {
				msgbox("提示", "请先在列表中选择要卸载的皮肤。", 0x40)
				return 0
			}
			if msgboxYesNo("确认卸载皮肤 “" + name + "” ？") {
				go func() {
					ssf := filepath.Join(allSkinDir(), name+".ssf")
					if _, err := os.Stat(ssf); err == nil {
						if _, err := ensureBackupFile(ssf, skinBackupDir(), name+".ssf"); err != nil {
							logf("delete skin: backup failed: %s: %v", ssf, err)
						}
					}
					if err := runSGTool("-line", "0", "-border", "--appid=skindelete", name); err != nil {
						logf("delete skin: start SGTool failed: %v", err)
					}
					time.Sleep(800 * time.Millisecond)
					if err := os.Remove(ssf); err != nil && !os.IsNotExist(err) {
						logf("delete skin: remove failed: %s: %v", ssf, err)
						postStatus("皮肤卸载不完整：文件删除失败")
					} else {
						logf("delete skin: ok: name=%s", name)
						postStatus("已卸载皮肤：" + name)
					}
					scanLists()
				}()
			}

		case 2001: // 安装词库
			f := openFile("搜狗细胞词库 (*.scel)\x00*.scel\x00所有文件 (*.*)\x00*.*\x00\x00", "选择要安装的细胞词库 (.scel)", "scel")
			if f == "" {
				return 0
			}
			base := filepath.Base(f)
			if !strings.EqualFold(filepath.Ext(base), ".scel") {
				msgbox("提示", "请选择 .scel 词库文件。", 0x40)
				return 0
			}
			postStatus("正在导入词库：" + base + " ...")
			go func() {
				// 重要：scdreg 不能带 `-line 0 -border`（实测该前缀会让它直接失败，
				// 返回 1 且不注册）。scdreg 只认 `--appid=scdreg -add "<scel>" -s`。
				// 只交给 scdreg：由它自行部署到用户 scd 目录，不再手动复制到
				// 程序 scd 目录（否则同一词库会被算作两条）。
				addErr := runSGToolWait("--appid=scdreg", "-add", f, "-s")
				// 关键：重建词库索引，否则新词库不生效
				_ = runSGToolWait("--appid=scdreg", "-update")

				// 不只信进程退出码：必须真的在用户/程序 scd 目录找到同内容文件。
				dest := findMatchingFile([]string{scdUserDir(), scdProgDir()}, f, ".scel")
				if dest == "" {
					// scdreg 没有把文件部署出来时，使用可持久化的文件部署作为兜底，
					// 再重建一次索引。这样重启后至少源文件仍在用户 scd 目录。
					if err := os.MkdirAll(scdUserDir(), 0755); err == nil {
						fallback := filepath.Join(scdUserDir(), base)
						if _, _, err := copyFileVerified(f, fallback); err == nil {
							logf("install dict: scdreg did not deploy, fallback copied: %s", fallback)
							_ = runSGToolWait("--appid=scdreg", "-update")
							dest = findMatchingFile([]string{scdUserDir(), scdProgDir()}, f, ".scel")
						} else {
							logf("install dict: fallback copy failed: %s: %v", fallback, err)
						}
					}
				}
				if dest == "" {
					logf("install dict: NOT VERIFIED: src=%s scdreg_err=%v", f, addErr)
					postStatus("词库导入失败：未在 scd 目录找到落盘文件")
					scanLists()
					return
				}
				if _, err := ensureBackupFile(dest, dictBackupDir(), filepath.Base(dest)); err != nil {
					logf("install dict: destination backup failed: %s: %v", dest, err)
				}
				hash, size, _ := fileDigest(dest)
				logf("install dict: verified: src=%s dest=%s bytes=%d sha256=%s scdreg_err=%v", f, dest, size, hash, addErr)
				if addErr != nil {
					postStatus("词库文件已持久落盘，但 scdreg 返回错误；请重启输入法验证：" + base)
				} else {
					postStatus("词库已导入并重建索引：" + base + "。若打不出新词，请重启一下输入法（切换中/英或注销重登）。")
				}
				scanLists()
			}()

		case 2002: // 卸载词库
			name := listSel(hDictList)
			if name == "" {
				msgbox("提示", "请先在列表中选择要卸载的词库。", 0x40)
				return 0
			}
			if msgboxYesNo("确认卸载词库 “" + name + "” ？") {
				go func() {
					for _, p := range []string{filepath.Join(scdUserDir(), name), filepath.Join(scdProgDir(), name)} {
						if _, err := os.Stat(p); err == nil {
							if _, err := ensureBackupFile(p, dictBackupDir(), name); err != nil {
								logf("delete dict: backup failed: %s: %v", p, err)
							}
						}
						if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
							logf("delete dict: remove failed: %s: %v", p, err)
						}
					}
					_ = runSGToolWait("--appid=scdreg", "-update")
					logf("delete dict: ok: name=%s", name)
					postStatus("已卸载词库并重建索引：" + name)
					scanLists()
				}()
			}

		case 3001:
			postStatus("正在刷新列表 ...")
			go scanLists()

		case 3002:
			go openFolder(allSkinDir())

		case 3003:
			go openFolder(scdUserDir())

		case 3004:
			pSendMessageW.Call(hwnd, WM_CLOSE, 0, 0)

		case 3005:
			go openURL(DOWNLOAD_URL)

		case 3007:
			go openURL(BLOG_URL)

		case 3008:
			postStatus("正在从备份恢复缺失资产 ...")
			go restoreAssetsFromBackup()

		case 4001: // 点击下载地址链接
			go openURL(DOWNLOAD_URL)

		case 4002: // 点击作者博客链接
			go openURL(BLOG_URL)

		case 3006:
			msgbox("使用说明", helpText, 0x40)
		}
		return 0

	case WM_CTLCOLORSTATIC:
		id := ctrlID(lparam)
		if id == 4001 || id == 4002 {
			pSetBkMode.Call(wparam, TRANSPARENT_BK)
			if id == 4002 {
				pSetTextColor.Call(wparam, COLOR_BLOG)
			} else {
				pSetTextColor.Call(wparam, COLOR_LINK)
			}
			br, _, _ := pGetStockObject.Call(HOLLOW_BRUSH)
			return br
		}

	case WM_SETCURSOR:
		id := ctrlID(wparam)
		if id == 4001 || id == 4002 {
			cur, _, _ := pLoadCursorW.Call(0, IDC_HAND)
			pSetCursor.Call(cur)
			return 1
		}

	case WM_CLOSE:
		pPostQuitMessage.Call(0)
		return 0

	case WM_DESTROY:
		pPostQuitMessage.Call(0)
		return 0
	}
	r, _, _ := pDefWindowProcW.Call(hwnd, uintptr(msg), wparam, lparam)
	return r
}
