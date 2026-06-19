use crate::host_arena::{HostSession, MoonHostFieldInit, MoonHostPtr, MoonHostRecordSpec, MoonHostRef};
use crate::{Artifact, Jit, MoonliftError, compile_object_binary};
use std::cell::RefCell;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::ptr;

#[repr(C)]
pub struct moonlift_jit_t {
    inner: Jit,
}

#[repr(C)]
pub struct moonlift_artifact_t {
    inner: Artifact,
}

#[repr(C)]
pub struct moonlift_bytes_t {
    data: *mut u8,
    len: usize,
}

#[repr(C)]
pub struct moonlift_host_session_t {
    inner: HostSession,
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::new("ok").expect("valid CString"));
}

fn set_last_error(message: impl Into<String>) {
    let mut text = message.into();
    if text.as_bytes().contains(&0) {
        text = text.replace('\0', "?");
    }
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = CString::new(text).unwrap_or_else(|_| CString::new("moonlift ffi error").unwrap());
    });
}

fn clear_last_error() {
    set_last_error("ok");
}

fn ok_int() -> c_int {
    clear_last_error();
    1
}

fn fail_int(msg: String) -> c_int {
    set_last_error(msg);
    0
}

fn fail_ptr(msg: String) -> *mut c_void {
    set_last_error(msg);
    ptr::null_mut()
}

fn fail_const_ptr(msg: String) -> *const c_void {
    set_last_error(msg);
    ptr::null()
}

fn require_mut_ptr<'a, T>(ptr: *mut T, name: &str) -> Result<&'a mut T, MoonliftError> {
    unsafe { ptr.as_mut() }
        .ok_or_else(|| MoonliftError(format!("{name} pointer was null")))
}

fn require_ptr<'a, T>(ptr: *const T, name: &str) -> Result<&'a T, MoonliftError> {
    unsafe { ptr.as_ref() }
        .ok_or_else(|| MoonliftError(format!("{name} pointer was null")))
}

fn read_cstr<'a>(ptr: *const c_char, name: &str) -> Result<String, MoonliftError> {
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map(|s| s.to_owned())
        .map_err(|e| MoonliftError(format!("{name} is not valid UTF-8: {e}")))
}

// =========================================================================
// C API: JIT
// =========================================================================

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_last_error_message() -> *const c_char {
    LAST_ERROR.with(|slot| {
        let s = slot.borrow();
        s.as_ptr()
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_new() -> *mut moonlift_jit_t {
    clear_last_error();
    let jit = Box::new(moonlift_jit_t {
        inner: Jit::new(),
    });
    Box::into_raw(jit)
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_free(jit: *mut moonlift_jit_t) {
    if !jit.is_null() {
        clear_last_error();
        unsafe { drop(Box::from_raw(jit)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_symbol(
    jit: *mut moonlift_jit_t,
    name: *const c_char,
    ptr: *const u8,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let jit = unsafe { (jit as *mut moonlift_jit_t).as_mut() }
            .ok_or_else(|| MoonliftError("moonlift_jit_t pointer was null".to_string()))?;
        let name = read_cstr(name, "symbol name")?;
        jit.inner.symbol(&name, ptr);
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_artifact_free(artifact: *mut moonlift_artifact_t) {
    if !artifact.is_null() {
        clear_last_error();
        unsafe { drop(Box::from_raw(artifact)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_compile_binary(
    jit: *mut moonlift_jit_t,
    data: *const u8,
    len: usize,
) -> *mut c_void {
    let result: Result<_, MoonliftError> = (|| {
        let jit = require_ptr(jit, "moonlift_jit_t")?;
        if data.is_null() {
            return Err(MoonliftError("binary data pointer was null".to_string()));
        }
        let buf = unsafe { std::slice::from_raw_parts(data, len) };
        let artifact = jit.inner.compile_binary(buf)?;
        Ok(Box::into_raw(Box::new(moonlift_artifact_t { inner: artifact })) as *mut c_void)
    })();
    match result {
        Ok(ptr) => { clear_last_error(); ptr }
        Err(err) => fail_ptr(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_artifact_getpointer(
    artifact: *mut moonlift_artifact_t,
    func: *const c_char,
) -> *const c_void {
    let result: Result<_, MoonliftError> = (|| {
        let artifact = unsafe { artifact.as_ref() }
            .ok_or_else(|| MoonliftError("moonlift_artifact_t pointer was null".to_string()))?;
        let func = read_cstr(func, "function id")?;
        artifact.inner.getpointer_by_name(&func)
    })();
    match result {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => fail_const_ptr(err.0),
    }
}

// =========================================================================
// C API: Object emission
// =========================================================================

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_object_compile_binary(
    data: *const u8,
    len: usize,
    module_name: *const c_char,
    out: *mut moonlift_bytes_t,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let out = unsafe { out.as_mut() }
            .ok_or_else(|| MoonliftError("moonlift_bytes_t output pointer was null".to_string()))?;
        if data.is_null() {
            return Err(MoonliftError("binary data pointer was null".to_string()));
        }
        let buf = unsafe { std::slice::from_raw_parts(data, len) };
        let module_name = if module_name.is_null() {
            "moonlift_object".to_string()
        } else {
            read_cstr(module_name, "object module name")?
        };
        let artifact = compile_object_binary(buf, &module_name)?;
        let mut bytes = artifact.into_bytes().into_boxed_slice();
        out.data = bytes.as_mut_ptr();
        out.len = bytes.len();
        std::mem::forget(bytes);
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_bytes_free(bytes: *mut moonlift_bytes_t) {
    if !bytes.is_null() {
        clear_last_error();
        let b = unsafe { Box::from_raw(bytes) };
        if !b.data.is_null() && b.len > 0 {
            unsafe { drop(Vec::from_raw_parts(b.data, b.len, b.len)); }
        }
    }
}

// =========================================================================
// C API: Host arena
// =========================================================================

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_new() -> *mut moonlift_host_session_t {
    clear_last_error();
    Box::into_raw(Box::new(moonlift_host_session_t {
        inner: HostSession::new(),
    }))
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_free(session: *mut moonlift_host_session_t) {
    if !session.is_null() {
        clear_last_error();
        unsafe { drop(Box::from_raw(session)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_id(session: *const moonlift_host_session_t) -> u64 {
    match require_ptr(session, "moonlift_host_session_t") {
        Ok(session) => {
            clear_last_error();
            session.inner.session_id()
        }
        Err(err) => {
            set_last_error(err.0);
            0
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_generation(session: *const moonlift_host_session_t) -> u32 {
    match require_ptr(session, "moonlift_host_session_t") {
        Ok(session) => {
            clear_last_error();
            session.inner.generation()
        }
        Err(err) => {
            set_last_error(err.0);
            0
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_reset(session: *mut moonlift_host_session_t) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let session = require_mut_ptr(session, "moonlift_host_session_t")?;
        session.inner.reset();
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_alloc_record(
    session: *mut moonlift_host_session_t,
    type_id: u32,
    tag: u32,
    size: usize,
    align: usize,
    out_ref: *mut MoonHostRef,
    out_ptr: *mut MoonHostPtr,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let session = require_mut_ptr(session, "moonlift_host_session_t")?;
        let out_ref = require_mut_ptr(out_ref, "MoonHostRef output")?;
        let out_ptr = require_mut_ptr(out_ptr, "MoonHostPtr output")?;
        let (r, p) = session.inner.alloc_record(type_id, tag, size, align)
            .map_err(MoonliftError)?;
        *out_ref = r;
        *out_ptr = p;
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_alloc_records(
    session: *mut moonlift_host_session_t,
    specs: *const MoonHostRecordSpec,
    specs_len: usize,
    fields: *const MoonHostFieldInit,
    fields_len: usize,
    out_refs: *mut MoonHostRef,
    out_ptrs: *mut MoonHostPtr,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let session = require_mut_ptr(session, "moonlift_host_session_t")?;
        if specs_len > 0 && specs.is_null() {
            return Err(MoonliftError("MoonHostRecordSpec input pointer was null".to_string()));
        }
        if fields_len > 0 && fields.is_null() {
            return Err(MoonliftError("MoonHostFieldInit input pointer was null".to_string()));
        }
        if specs_len > 0 && out_refs.is_null() {
            return Err(MoonliftError("MoonHostRef output pointer was null".to_string()));
        }
        if specs_len > 0 && out_ptrs.is_null() {
            return Err(MoonliftError("MoonHostPtr output pointer was null".to_string()));
        }

        let specs = unsafe { std::slice::from_raw_parts(specs, specs_len) };
        let fields = unsafe { std::slice::from_raw_parts(fields, fields_len) };
        let out_refs = unsafe { std::slice::from_raw_parts_mut(out_refs, specs_len) };
        let out_ptrs = unsafe { std::slice::from_raw_parts_mut(out_ptrs, specs_len) };

        for (i, spec) in specs.iter().copied().enumerate() {
            let end = spec.first_field
                .checked_add(spec.field_count)
                .ok_or_else(|| MoonliftError(format!("host record spec {i} field range overflow")))?;
            if end > fields.len() {
                return Err(MoonliftError(format!(
                    "host record spec {i} field range [{}, {}) exceeds field count {}",
                    spec.first_field,
                    end,
                    fields.len()
                )));
            }
            let (r, p) = session.inner.alloc_record(spec.type_id, spec.tag, spec.size, spec.align)
                .map_err(MoonliftError)?;
            for field in &fields[spec.first_field..end] {
                session.inner.write_field(r, *field).map_err(MoonliftError)?;
            }
            out_refs[i] = r;
            out_ptrs[i] = p;
        }
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_ptr_for_ref(
    session: *const moonlift_host_session_t,
    r: MoonHostRef,
    out_ptr: *mut MoonHostPtr,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let session = require_ptr(session, "moonlift_host_session_t")?;
        let out_ptr = require_mut_ptr(out_ptr, "MoonHostPtr output")?;
        let p = session.inner.ptr_for_ref(r).map_err(MoonliftError)?;
        *out_ptr = p;
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}
