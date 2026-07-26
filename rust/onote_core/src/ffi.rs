//! A tiny C-ABI shim over the core, for calling from Dart via `dart:ffi`.
//!
//! We expose the same three operations as [`crate::api`], but through a plain
//! C interface (raw `*const c_char` in, heap `*mut c_char` out) instead of
//! flutter_rust_bridge. This is the path the app actually links today: it needs
//! no codegen step, so the Dart bindings are hand-written and fully under our
//! control (see `app/lib/core/onote_ffi.dart`). The `bridge`-feature `api`
//! module remains for a future FRB-based integration.
//!
//! Ownership contract: every function that returns `*mut c_char` transfers
//! ownership to the caller, who MUST return it via [`onote_core_string_free`].
//! Input pointers are borrowed for the duration of the call only.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Core version string, e.g. "0.1.0". Caller frees the result.
///
/// # Safety
/// The returned pointer must be freed with [`onote_core_string_free`].
#[no_mangle]
pub extern "C" fn onote_core_version() -> *mut c_char {
    into_c(crate::core_version().to_string())
}

/// Merge two page-mirror JSON documents. On malformed input, returns the
/// `local` document unchanged (a sync round should degrade, never crash).
/// Caller frees the result.
///
/// # Safety
/// `local` and `remote` must be valid NUL-terminated C strings (or null).
/// The returned pointer must be freed with [`onote_core_string_free`].
#[no_mangle]
pub unsafe extern "C" fn onote_core_merge(
    local: *const c_char,
    remote: *const c_char,
) -> *mut c_char {
    let local = from_c(local);
    let remote = from_c(remote);
    // A panic unwinding across an `extern "C"` boundary is UB. Catch it here
    // (as `import_one` already does) so any unexpected panic degrades to the
    // local doc unchanged instead of tearing down the host app.
    let merged = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        crate::mirror::merge_json(&local, &remote).unwrap_or_else(|_| local.clone())
    }))
    .unwrap_or_else(|_| local.clone());
    into_c(merged)
}

/// Stable content hash of a page-mirror JSON document (empty string on
/// malformed input). Caller frees the result.
///
/// # Safety
/// `mirror` must be a valid NUL-terminated C string (or null). The returned
/// pointer must be freed with [`onote_core_string_free`].
#[no_mangle]
pub unsafe extern "C" fn onote_core_page_hash(mirror: *const c_char) -> *mut c_char {
    let mirror = from_c(mirror);
    // Panic-guarded so a hash failure can't unwind across the C boundary (UB).
    let hash = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        crate::ids::page_content_hash(&mirror).unwrap_or_default()
    }))
    .unwrap_or_default();
    into_c(hash)
}

/// Import a OneNote `.one` section file. Takes the raw file bytes and returns
/// a JSON string: `{ok, error?, pages:[{title, texts:[...],
/// images:[{name, data_base64}]}]}`. Caller frees the result.
///
/// # Safety
/// `ptr` must point to `len` readable bytes (or be null with len 0). The
/// returned pointer must be freed with [`onote_core_string_free`].
#[no_mangle]
pub unsafe extern "C" fn onote_core_import_one(ptr: *const u8, len: usize) -> *mut c_char {
    let bytes: &[u8] = if ptr.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(ptr, len)
    };
    into_c(crate::onenote::import_one_json(bytes))
}

/// Import a OneNote `.onepkg` notebook package (a cabinet of `.one` sections).
/// Takes the raw file bytes and returns a JSON string:
/// `{ok, error?, sections:[{name, group?, section:{ok, pages:[…]}}]}`.
/// Caller frees the result.
///
/// # Safety
/// `ptr` must point to `len` readable bytes (or be null with len 0). The
/// returned pointer must be freed with [`onote_core_string_free`].
#[no_mangle]
pub unsafe extern "C" fn onote_core_import_onepkg(ptr: *const u8, len: usize) -> *mut c_char {
    let bytes: &[u8] = if ptr.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(ptr, len)
    };
    into_c(crate::onepkg::import_onepkg_json(bytes))
}

/// Free a string previously returned by any `onote_core_*` function.
///
/// # Safety
/// `ptr` must be a pointer returned by this library and not already freed.
#[no_mangle]
pub unsafe extern "C" fn onote_core_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

fn into_c(s: String) -> *mut c_char {
    // Interior NULs can't occur in our JSON/version output; if they somehow do,
    // hand back an empty string rather than panicking across the FFI boundary.
    CString::new(s).unwrap_or_default().into_raw()
}

unsafe fn from_c(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    CStr::from_ptr(p).to_string_lossy().into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::ffi::CString;

    unsafe fn take(ptr: *mut c_char) -> String {
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        onote_core_string_free(ptr);
        s
    }

    #[test]
    fn version_round_trips_through_ffi() {
        unsafe {
            assert_eq!(take(onote_core_version()), "0.1.0");
        }
    }

    #[test]
    fn merge_and_hash_through_ffi() {
        let local = CString::new(
            json!({"blocks":[{"id":"a","type":"text","updatedAt":1}]}).to_string(),
        )
        .unwrap();
        let remote = CString::new(
            json!({"blocks":[{"id":"a","type":"text","updatedAt":9},
                             {"id":"b","type":"text","updatedAt":3}]})
            .to_string(),
        )
        .unwrap();
        unsafe {
            let merged = take(onote_core_merge(local.as_ptr(), remote.as_ptr()));
            assert!(merged.contains("\"b\""), "union kept: {merged}");
            // Newer 'a' (updatedAt 9) won.
            assert!(merged.contains("\"updatedAt\":9"));

            let h1 = take(onote_core_page_hash(local.as_ptr()));
            let h2 = take(onote_core_page_hash(local.as_ptr()));
            assert_eq!(h1, h2);
            assert!(!h1.is_empty());
        }
    }

    #[test]
    fn null_input_is_safe() {
        unsafe {
            // Null pointers degrade to empty strings; empty isn't valid JSON,
            // so merge returns the (empty) local unchanged — no crash, no panic.
            let out = take(onote_core_merge(std::ptr::null(), std::ptr::null()));
            assert_eq!(out, "");
            let h = take(onote_core_page_hash(std::ptr::null()));
            assert_eq!(h, "");
        }
    }
}
