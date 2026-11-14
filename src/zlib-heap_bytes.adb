with Ada.Unchecked_Deallocation;

package body Zlib.Heap_Bytes is

   procedure Free is new Ada.Unchecked_Deallocation
     (Byte_Array, Byte_Array_Access);

   overriding procedure Finalize (Item : in out Holder) is
   begin
      Free (Item.Data);
   end Finalize;

   procedure Allocate (Item : in out Holder; Length : Natural) is
   begin
      Free (Item.Data);
      Item.Data := new Byte_Array (1 .. Length);
   end Allocate;

   function Vector_To_Array (Source : Vectors.Vector) return Byte_Array is
      Copy  : Holder;
      Index : Natural := 0;
   begin
      Allocate (Copy, Natural (Vectors.Length (Source)));
      for Item of Source loop
         Index := Index + 1;
         Copy.Data (Index) := Item;
      end loop;
      return Copy.Data.all;
   end Vector_To_Array;

end Zlib.Heap_Bytes;
