with Ada.Containers.Vectors;
with Ada.Finalization;

package Zlib.Heap_Bytes is
   --  Support level: private internal implementation.
   --  Heap storage for byte arrays as large as a whole payload.
   --
   --  A named local Byte_Array sized by a payload is laid out in the primary
   --  stack frame of whoever declares it, and a worker thread's stack may be
   --  1 MiB or less: decoding a few megabytes there overflowed it. Storage
   --  taken from here lives on the heap and is released when its Holder goes
   --  out of scope, however that scope ends. A function hands the bytes back
   --  with "return Holder.Data.all" (or a slice of it): GNAT copies an
   --  unconstrained result straight onto the secondary stack, which is
   --  heap-backed as well, so no payload-sized object ever sits on the primary
   --  stack.

   type Byte_Array_Access is access Byte_Array;

   type Holder is new Ada.Finalization.Limited_Controlled with record
      Data : Byte_Array_Access;
   end record;
   --  Owns Data; finalization frees it.

   overriding procedure Finalize (Item : in out Holder);
   --  Free the held storage, if any.
   --  @param Item the holder

   procedure Allocate (Item : in out Holder; Length : Natural);
   --  Replace the held storage with a fresh, uninitialized array 1 .. Length.
   --  @param Item   the holder
   --  @param Length number of bytes; zero gives an empty array

   generic
      with package Vectors is new Ada.Containers.Vectors
        (Element_Type => Byte, others => <>);
   function Vector_To_Array (Source : Vectors.Vector) return Byte_Array;
   --  The elements of a byte vector, in order, as an array indexed from 1,
   --  built without a payload-sized object on the primary stack.
   --  @param Source the vector
   --  @return its elements

end Zlib.Heap_Bytes;
