package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCopyFileVerified(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "source.ssf")
	dst := filepath.Join(dir, "nested", "dest.ssf")
	want := []byte("sogou-asset-test-payload")
	if err := os.WriteFile(src, want, 0644); err != nil {
		t.Fatal(err)
	}

	hash, size, err := copyFileVerified(src, dst)
	if err != nil {
		t.Fatal(err)
	}
	if size != int64(len(want)) {
		t.Fatalf("size = %d, want %d", size, len(want))
	}
	if hash == "" {
		t.Fatal("empty hash")
	}
	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(want) {
		t.Fatalf("content = %q, want %q", got, want)
	}
}

func TestFindMatchingFile(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "source.scel")
	otherDir := filepath.Join(dir, "other")
	if err := os.MkdirAll(otherDir, 0755); err != nil {
		t.Fatal(err)
	}
	payload := []byte("dictionary-payload")
	if err := os.WriteFile(src, payload, 0644); err != nil {
		t.Fatal(err)
	}
	match := filepath.Join(otherDir, "renamed.scel")
	if err := os.WriteFile(match, payload, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(otherDir, "different.scel"), []byte("x"), 0644); err != nil {
		t.Fatal(err)
	}

	if got := findMatchingFile([]string{otherDir}, src, ".scel"); got != match {
		t.Fatalf("findMatchingFile = %q, want %q", got, match)
	}
}

func TestSkinRegistered(t *testing.T) {
	root := t.TempDir()
	t.Setenv("USERPROFILE", root)
	dir := filepath.Join(root, "AppData", "LocalLow", "SogouPY")
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	ini := "[setting]\r\ncnt=1\r\n\r\n[skin0]\r\nname=测试皮肤\r\n"
	if err := os.WriteFile(filepath.Join(dir, "SkinRecent.ini"), []byte(ini), 0644); err != nil {
		t.Fatal(err)
	}
	if !skinRegistered("测试皮肤") {
		t.Fatal("expected skin to be registered")
	}
	if skinRegistered("不存在的皮肤") {
		t.Fatal("unexpected skin registration")
	}
}
