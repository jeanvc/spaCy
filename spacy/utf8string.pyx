from libc.string cimport memcpy

from murmurhash.mrmr cimport hash64

import ujson


cdef class StringStore:
    def __init__(self):
        self.mem = Pool()
        self.table = PreshMap()
        self._resize_at = 10000
        self.strings = <Utf8Str*>self.mem.alloc(self._resize_at, sizeof(Utf8Str))
        self.size = 1

    property size:
        def __get__(self):
            return self.size-1

    def __getitem__(self, string_or_id):
        cdef bytes byte_string
        cdef Utf8Str* utf8str
        if type(string_or_id) == int or type(string_or_id) == long:
            if string_or_id < 1 or string_or_id >= self.size:
                raise IndexError(string_or_id)
            utf8str = &self.strings[<int>string_or_id]
            return utf8str.chars[:utf8str.length]
        elif type(string_or_id) == bytes:
            utf8str = self.intern(<char*>string_or_id, len(string_or_id))
            return utf8str.i
        else:
            raise TypeError(type(string_or_id))

    cdef Utf8Str* intern(self, char* chars, int length) except NULL:
        # 0 means missing, but we don't bother offsetting the index. We waste
        # slot 0 to simplify the code, because it doesn't matter.
        assert length != 0
        cdef hash_t key = hash64(chars, length * sizeof(char), 0)
        cdef void* value = self.table.get(key)
        cdef size_t i
        if value == NULL:
            if self.size == self._resize_at:
                self._resize_at *= 2
                self.strings = <Utf8Str*>self.mem.realloc(self.strings, self._resize_at * sizeof(Utf8Str))
            i = self.size
            self.strings[i].i = self.size
            self.strings[i].key = key
            self.strings[i].chars = <char*>self.mem.alloc(length, sizeof(char))
            memcpy(self.strings[i].chars, chars, length)
            self.strings[i].length = length
            self.table.set(key, <void*>self.size)
            self.size += 1
        else:
            i = <size_t>value
        return &self.strings[i]

    def dump(self, loc):
        strings = []
        cdef Utf8Str* string
        cdef bytes py_string
        print "Dump strings"
        for i in range(self.size):
            string = &self.strings[i]
            py_string = string.chars[:string.length]
            strings.append(py_string)
        print len(strings)
        with open(loc, 'w') as file_:
            ujson.dump(strings, file_, ensure_ascii=False)

    def load(self, loc):
        with open(loc) as file_:
            strings = ujson.load(file_)
        for string in strings[1:]:
            self.intern(string, len(string))