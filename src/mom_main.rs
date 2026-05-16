// MOM product binary.
//
// This binary links the precompiled native MOM object and calls its exported C
// ABI directly.  It intentionally does not embed or require hosted Moonlift Lua
// compiler modules.

use std::env;
use std::ffi::c_void;
use std::fs;
use std::path::PathBuf;

unsafe extern "C" {
    fn mom_hello() -> i32;
    #[allow(dead_code)]
    fn mom_luaopen_moonlift(state: *mut c_void) -> i32;
    fn mom_compile_source_to_wire_internal(
        src: *mut u8,
        src_len: usize,
        wire_out: *mut u8,
        wire_cap: usize,
        work_buf: *mut u8,
        work_cap: usize,
    ) -> i32;
    fn mom_compile_source_to_object_internal(
        src: *mut u8,
        src_len: usize,
        obj_out: *mut u8,
        obj_cap: usize,
        work_buf: *mut u8,
        work_cap: usize,
    ) -> i32;
    #[allow(dead_code)]
    fn mom_compile_source_to_artifact_internal(
        src: *mut u8,
        src_len: usize,
        diags: *mut u8,
        diag_cap: usize,
        work_buf: *mut u8,
        work_cap: usize,
    ) -> i32;
    fn mom_debug_index_arithmetic(buf: *mut u8, cap: usize) -> i32;
}

#[allow(dead_code)]
fn keep_rust_backend_symbols_linked() {
    // The precompiled MOM object imports these Rust backend FFI symbols.  Taking
    // their addresses here makes the symbols part of the final product binary
    // even before the native driver calls all paths.
    let _ = moonlift::ffi::moonlift_jit_new as extern "C" fn() -> *mut moonlift::ffi::moonlift_jit_t;
    let _ = moonlift::ffi::moonlift_jit_free as extern "C" fn(*mut moonlift::ffi::moonlift_jit_t);
    let _ = moonlift::ffi::moonlift_jit_compile_binary as extern "C" fn(*mut moonlift::ffi::moonlift_jit_t, *const u8, usize) -> *mut moonlift::ffi::moonlift_artifact_t;
    let _ = moonlift::ffi::moonlift_artifact_getpointer as extern "C" fn(*const moonlift::ffi::moonlift_artifact_t, *const std::ffi::c_char) -> *const c_void;
    let _ = moonlift::ffi::moonlift_artifact_free as extern "C" fn(*mut moonlift::ffi::moonlift_artifact_t);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Status,
    Run,
    Object,
}

#[derive(Debug)]
struct Opts {
    mode: Mode,
    input: Option<PathBuf>,
    output: Option<PathBuf>,
    call: String,
    ret: String,
    args_i32: Vec<i32>,
}

fn usage(out: &mut dyn std::io::Write) {
    let _ = writeln!(out, "usage:");
    let _ = writeln!(out, "  mom status");
    let _ = writeln!(out, "  mom run [--call NAME] [--ret i32|void] [--arg-i32 N ...] FILE");
    let _ = writeln!(out, "  mom --emit-object -o OUT.o [--module-name NAME] FILE");
}

fn parse_args() -> Result<Opts, String> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() || args.iter().any(|a| a == "--help" || a == "-h") {
        let mut out = std::io::stdout();
        usage(&mut out);
        std::process::exit(0);
    }

    let mut opts = Opts {
        mode: Mode::Run,
        input: None,
        output: None,
        call: "main".to_string(),
        ret: "i32".to_string(),
        args_i32: Vec::new(),
    };

    let mut i = 0usize;
    if args[i] == "status" {
        opts.mode = Mode::Status;
        return Ok(opts);
    }
    if args[i] == "run" {
        opts.mode = Mode::Run;
        i += 1;
    }

    while i < args.len() {
        match args[i].as_str() {
            "--emit-object" => opts.mode = Mode::Object,
            "-o" => {
                i += 1;
                let Some(v) = args.get(i) else { return Err("-o expects an output path".to_string()); };
                opts.output = Some(PathBuf::from(v));
            }
            "--module-name" => {
                // Accepted for CLI stability; native object naming is owned by
                // the native driver once object emission is fully wired.
                i += 1;
                if args.get(i).is_none() { return Err("--module-name expects a value".to_string()); }
            }
            "--call" => {
                i += 1;
                let Some(v) = args.get(i) else { return Err("--call expects a function name".to_string()); };
                opts.call = v.clone();
            }
            "--ret" => {
                i += 1;
                let Some(v) = args.get(i) else { return Err("--ret expects i32 or void".to_string()); };
                opts.ret = v.clone();
            }
            "--arg-i32" => {
                i += 1;
                let Some(v) = args.get(i) else { return Err("--arg-i32 expects an integer".to_string()); };
                opts.args_i32.push(v.parse::<i32>().map_err(|_| format!("invalid --arg-i32 value: {v}"))?);
            }
            s if s.starts_with('-') => return Err(format!("unknown option {s}")),
            s => {
                if opts.input.is_some() { return Err(format!("unexpected argument {s}")); }
                opts.input = Some(PathBuf::from(s));
            }
        }
        i += 1;
    }

    Ok(opts)
}

fn status() -> i32 {
    let hello = unsafe { mom_hello() };
    let mut probe_buf = [0u8; 2];
    let index_probe = unsafe { mom_debug_index_arithmetic(probe_buf.as_mut_ptr(), probe_buf.len()) };

    let mut src = b"func main() -> i32\n  return 0\nend\n".to_vec();
    let mut wire = vec![0u8; 64 * 1024];
    let mut work = vec![0u8; 4 * 1024 * 1024];
    let pipeline_probe = unsafe {
        mom_compile_source_to_wire_internal(
            src.as_mut_ptr(),
            src.len(),
            wire.as_mut_ptr(),
            wire.len(),
            work.as_mut_ptr(),
            work.len(),
        )
    };

    println!("mom integration: precompiled native MOM object linked");
    println!("mom_hello: {hello}");
    println!("mom index arithmetic probe: {index_probe}");
    println!("mom native pipeline probe: {pipeline_probe}");
    if hello == 42 && index_probe == 40 && pipeline_probe > 0 { 0 } else { 1 }
}

fn compile_wire_smoke(source: &mut [u8]) -> Result<Vec<u8>, i32> {
    let mut wire = vec![0u8; source.len().saturating_mul(64).max(64 * 1024)];
    let mut work = vec![0u8; 4 * 1024 * 1024];
    let rc = unsafe {
        mom_compile_source_to_wire_internal(
            source.as_mut_ptr(),
            source.len(),
            wire.as_mut_ptr(),
            wire.len(),
            work.as_mut_ptr(),
            work.len()
        )
    };
    if rc > 0 {
        wire.truncate(rc as usize);
        Ok(wire)
    } else {
        Err(rc)
    }
}

fn emit_object(path: PathBuf, output: PathBuf) -> Result<(), String> {
    let mut source = fs::read(&path).map_err(|e| format!("unable to read {}: {e}", path.display()))?;
    let mut obj = vec![0u8; source.len().saturating_mul(128).max(128 * 1024)];
    let mut work = vec![0u8; 4 * 1024 * 1024];
    let rc = unsafe {
        mom_compile_source_to_object_internal(
            source.as_mut_ptr(),
            source.len(),
            obj.as_mut_ptr(),
            obj.len(),
            work.as_mut_ptr(),
            work.len()
        )
    };
    if rc <= 0 {
        return Err(format!("native MOM object emission failed with status {rc}"));
    }
    obj.truncate(rc as usize);
    fs::write(&output, &obj).map_err(|e| format!("unable to write {}: {e}", output.display()))?;
    println!("{}", output.display());
    Ok(())
}

fn run_file(opts: &Opts) -> Result<(), String> {
    if opts.ret != "i32" && opts.ret != "void" {
        return Err(format!("unsupported --ret {}; expected i32 or void", opts.ret));
    }

    let input = opts.input.as_ref().ok_or_else(|| "missing input file".to_string())?;
    let mut source = fs::read(input).map_err(|e| format!("unable to read {}: {e}", input.display()))?;
    let wire = compile_wire_smoke(&mut source)
        .map_err(|rc| format!("native MOM wire compilation failed with status {rc}"))?;

    let jit = moonlift::Jit::new();
    let artifact = jit
        .compile_binary(&wire)
        .map_err(|e| format!("native MOM backend compilation failed: {}", e.0))?;

    let ptr = artifact
        .getpointer_by_name(&opts.call)
        .map_err(|e| format!("native MOM entry point lookup failed: {}", e.0))?;

    if opts.ret == "void" {
        match opts.args_i32.as_slice() {
            [] => { let f: extern "C" fn() = unsafe { std::mem::transmute(ptr) }; f(); }
            [a] => { let f: extern "C" fn(i32) = unsafe { std::mem::transmute(ptr) }; f(*a); }
            [a, b] => { let f: extern "C" fn(i32, i32) = unsafe { std::mem::transmute(ptr) }; f(*a, *b); }
            [a, b, c] => { let f: extern "C" fn(i32, i32, i32) = unsafe { std::mem::transmute(ptr) }; f(*a, *b, *c); }
            [a, b, c, d] => { let f: extern "C" fn(i32, i32, i32, i32) = unsafe { std::mem::transmute(ptr) }; f(*a, *b, *c, *d); }
            _ => return Err("native MOM run supports at most four i32 arguments".to_string()),
        }
    } else {
        let result = match opts.args_i32.as_slice() {
            [] => { let f: extern "C" fn() -> i32 = unsafe { std::mem::transmute(ptr) }; f() }
            [a] => { let f: extern "C" fn(i32) -> i32 = unsafe { std::mem::transmute(ptr) }; f(*a) }
            [a, b] => { let f: extern "C" fn(i32, i32) -> i32 = unsafe { std::mem::transmute(ptr) }; f(*a, *b) }
            [a, b, c] => { let f: extern "C" fn(i32, i32, i32) -> i32 = unsafe { std::mem::transmute(ptr) }; f(*a, *b, *c) }
            [a, b, c, d] => { let f: extern "C" fn(i32, i32, i32, i32) -> i32 = unsafe { std::mem::transmute(ptr) }; f(*a, *b, *c, *d) }
            _ => return Err("native MOM run supports at most four i32 arguments".to_string()),
        };
        println!("{}", result);
    }
    Ok(())
}

fn main() {
    keep_rust_backend_symbols_linked();

    let opts = match parse_args() {
        Ok(opts) => opts,
        Err(e) => {
            eprintln!("{e}");
            let mut err = std::io::stderr();
            usage(&mut err);
            std::process::exit(2);
        }
    };

    let code = match opts.mode {
        Mode::Status => status(),
        Mode::Object => {
            let input = match opts.input.clone() {
                Some(p) => p,
                None => { eprintln!("missing input file"); std::process::exit(2); }
            };
            let output = match opts.output.clone() {
                Some(p) => p,
                None => { eprintln!("--emit-object requires -o OUT.o"); std::process::exit(2); }
            };
            match emit_object(input, output) {
                Ok(()) => 0,
                Err(e) => { eprintln!("{e}"); 1 }
            }
        }
        Mode::Run => match run_file(&opts) {
            Ok(()) => 0,
            Err(e) => { eprintln!("{e}"); 1 }
        },
    };
    std::process::exit(code);
}
