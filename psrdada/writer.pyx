# file: writer.pyx
"""
Writer class.

Implements writing header and data to an existing PSRDada ringbuffer.
"""

from cpython.buffer cimport PyBUF_WRITE
cimport dada_hdu
from .ringbuffer cimport Ringbuffer

from .exceptions import PSRDadaError

cdef extern from "<Python.h>":
    ctypedef struct PyObject:
        pass
    PyObject *PyMemoryView_FromMemory(char *mem, Py_ssize_t size, int flags)

cdef extern from "<string.h>":
    char *strncpy(char *dest, const char *src, size_t n)

cdef class Writer(Ringbuffer):
    """
    Writer class.

    Implements writing header and data to an existing PSRDada ringbuffer.
    """
    def connect(self, key):
        """Connect to a PSR DADA ringbuffer with the specified key, and lock it for writing"""
        super().connect(key)

        if dada_hdu.dada_hdu_lock_write(self._c_dada_hdu) < 0:
            raise PSRDadaError("ERROR in dada_hdu_lock_write")

    def disconnect(self):
        """Disconnect from PSR DADA ringbuffer"""
        dada_hdu.dada_hdu_unlock_write(self._c_dada_hdu)

        super().disconnect()

    def setHeader(self, header):
        """Write header to the Ringbuffer"""
        cdef char * c_string = dada_hdu.ipcbuf_get_next_write (self._c_dada_hdu.header_block)
        bufsz = dada_hdu.ipcbuf_get_bufsz(self._c_dada_hdu.header_block)

        lines = []
        for key in header:
            # join key value on a space
            line = key + ' ' + header[key]
            lines.append(line)

            # keep a copy for the Writer class
            self.header[key] = header[key]

        # join lines on newline, convert to ascii bytes
        py_string = '\n'.join(lines).encode('ascii')

        # copy to the header page and done
        strncpy(c_string, py_string, bufsz)
        dada_hdu.ipcbuf_mark_filled (self._c_dada_hdu.header_block, len(py_string))

    def getNextPage(self):
        """Return a memoryview on the next available ringbuffer page"""
        cdef dada_hdu.ipcbuf_t *ipcbuf = <dada_hdu.ipcbuf_t *> self._c_dada_hdu.data_block

        cdef char * c_page = dada_hdu.ipcbuf_get_next_write (ipcbuf)
        self._bufsz = dada_hdu.ipcbuf_get_bufsz(ipcbuf)

        return <object> PyMemoryView_FromMemory(c_page, self._bufsz, PyBUF_WRITE)

    def markFilled(self):
        cdef dada_hdu.ipcbuf_t *ipcbuf = <dada_hdu.ipcbuf_t *> self._c_dada_hdu.data_block
        dada_hdu.ipcbuf_mark_filled (ipcbuf, self._bufsz)
