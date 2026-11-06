"""Write Ogg Vorbis via libsndfile (ctypes) since this ffmpeg build lacks libvorbis."""
import ctypes, numpy as np
_lib = ctypes.CDLL('/opt/homebrew/lib/libsndfile.dylib')
class SF_INFO(ctypes.Structure):
    _fields_ = [('frames', ctypes.c_int64), ('samplerate', ctypes.c_int), ('channels', ctypes.c_int),
                ('format', ctypes.c_int), ('sections', ctypes.c_int), ('seekable', ctypes.c_int)]
SF_FORMAT_OGG = 0x200000; SF_FORMAT_VORBIS = 0x0060; SFM_WRITE = 0x20
SFC_SET_VBR_ENCODING_QUALITY = 0x1300
_lib.sf_open.restype = ctypes.c_void_p
_lib.sf_open.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(SF_INFO)]
_lib.sf_writef_float.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int64]
_lib.sf_writef_float.restype = ctypes.c_int64
_lib.sf_command.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
_lib.sf_close.argtypes = [ctypes.c_void_p]
_lib.sf_strerror.restype = ctypes.c_char_p
_lib.sf_strerror.argtypes = [ctypes.c_void_p]
def write_ogg(path, x, sr=44100, quality=0.6):
    x = np.asarray(x, dtype=np.float32)
    if x.ndim == 1: x = x[:, None]
    x = np.ascontiguousarray(np.clip(x, -1.0, 1.0))
    info = SF_INFO(0, sr, x.shape[1], SF_FORMAT_OGG | SF_FORMAT_VORBIS, 0, 0)
    h = _lib.sf_open(path.encode(), SFM_WRITE, ctypes.byref(info))
    if not h: raise RuntimeError('sf_open failed: %s' % _lib.sf_strerror(None))
    q = ctypes.c_double(quality)
    _lib.sf_command(h, SFC_SET_VBR_ENCODING_QUALITY, ctypes.byref(q), ctypes.sizeof(q))
    n = _lib.sf_writef_float(h, x.ctypes.data, x.shape[0])
    _lib.sf_close(h)
    if n != x.shape[0]: raise RuntimeError('short write')
if __name__ == '__main__':
    import sys
    t = np.arange(44100*2)/44100
    write_ogg(sys.argv[1], np.stack([0.5*np.sin(2*np.pi*440*t)]*2, 1))
