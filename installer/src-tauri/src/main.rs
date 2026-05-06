// Entry point for the BratanOS Flasher binary.
// All app logic lives in lib.rs so the same code can be unit-tested.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    bratan_flasher_lib::run();
}
