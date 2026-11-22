"""Run native Godot on an inactive Windows desktop, with audio disabled."""
import ctypes
from ctypes import wintypes as w
import json
import msvcrt
import os
import pathlib
import secrets
import subprocess
import time

class SI(ctypes.Structure):
    _fields_=[('cb',w.DWORD),('reserved',w.LPWSTR),('desktop',w.LPWSTR),('title',w.LPWSTR),
              ('x',w.DWORD),('y',w.DWORD),('width',w.DWORD),('height',w.DWORD),('cols',w.DWORD),
              ('rows',w.DWORD),('fill',w.DWORD),('flags',w.DWORD),('show',w.WORD),
              ('reserved2',w.WORD),('bytes',ctypes.c_void_p),('stdin',w.HANDLE),('stdout',w.HANDLE),('stderr',w.HANDLE)]
class PI(ctypes.Structure):
    _fields_=[('process',w.HANDLE),('thread',w.HANDLE),('pid',w.DWORD),('tid',w.DWORD)]

def run(args,log,timeout=90):
    k=ctypes.windll.kernel32;u=ctypes.windll.user32
    u.CreateDesktopW.argtypes=[w.LPCWSTR,w.LPCWSTR,ctypes.c_void_p,w.DWORD,w.DWORD,ctypes.c_void_p]
    u.CreateDesktopW.restype=w.HANDLE;u.CloseDesktop.argtypes=[w.HANDLE]
    k.CreateProcessW.argtypes=[w.LPCWSTR,w.LPWSTR,ctypes.c_void_p,ctypes.c_void_p,w.BOOL,w.DWORD,ctypes.c_void_p,w.LPCWSTR,ctypes.POINTER(SI),ctypes.POINTER(PI)]
    k.WaitForSingleObject.argtypes=[w.HANDLE,w.DWORD];k.CloseHandle.argtypes=[w.HANDLE]
    k.TerminateProcess.argtypes=[w.HANDLE,w.UINT];k.GetExitCodeProcess.argtypes=[w.HANDLE,ctypes.POINTER(w.DWORD)]
    name='BurningChariotHD_QA_'+secrets.token_hex(6);desktop=u.CreateDesktopW(name,None,None,0,0x1ff,None)
    if not desktop:raise ctypes.WinError()
    pi=PI();log=pathlib.Path(log);log.parent.mkdir(parents=True,exist_ok=True)
    args=list(map(str,args))
    try:
        with log.open('wb') as output,open(os.devnull,'rb') as empty:
            inp=msvcrt.get_osfhandle(empty.fileno());out=msvcrt.get_osfhandle(output.fileno())
            os.set_handle_inheritable(inp,True);os.set_handle_inheritable(out,True)
            si=SI();si.cb=ctypes.sizeof(si);si.desktop=name;si.flags=0x100;si.stdin=inp;si.stdout=si.stderr=out
            if not k.CreateProcessW(args[0],ctypes.create_unicode_buffer(subprocess.list2cmdline(args)),None,None,True,subprocess.CREATE_NO_WINDOW,None,str(pathlib.Path(args[0]).parent),ctypes.byref(si),ctypes.byref(pi)):raise ctypes.WinError()
            k.CloseHandle(pi.thread);pi.thread=None;deadline=time.monotonic()+timeout
            while k.WaitForSingleObject(pi.process,100)!=0:
                if time.monotonic()>deadline:raise TimeoutError('Silent native Godot test timed out')
            code=w.DWORD();assert k.GetExitCodeProcess(pi.process,ctypes.byref(code))
            driver=args[args.index('--audio-driver')+1] if '--audio-driver' in args else 'default'
            return dict(exit_code=code.value,log=str(log),private_desktop=True,audio_driver=driver)
    finally:
        if pi.process:
            if k.WaitForSingleObject(pi.process,0)!=0:k.TerminateProcess(pi.process,1)
            k.CloseHandle(pi.process)
        u.CloseDesktop(desktop)
