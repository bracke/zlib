with Ada.Streams; use Ada.Streams;
package body Zlib.Sliding_Window is

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset
   is
   begin
      if Data'Length = 0 then
         return Data'First;
      elsif Data'First = Ada.Streams.Stream_Element_Offset'First then
         return Data'First;
      else
         return Data'First - 1;
      end if;
   end Before_First;

   function Add_Mod
     (Value : Natural;
      Add   : Natural;
      Modulus : Natural)
      return Natural
   is
   begin
      return (Value + Add) mod Modulus;
   end Add_Mod;

   function Back_Index
     (W        : Window;
      Distance : Natural)
      return History_Index
   is
   begin
      return History_Index ((W.History_Next + Window_Size - Distance) mod Window_Size);
   end Back_Index;

   procedure Enqueue_Pending
     (W : in out Window;
      B : Ada.Streams.Stream_Element)
   is
      Pos : constant Pending_Index :=
        Pending_Index (Add_Mod (W.Pending_First, W.Pending_Count, Pending_Capacity));
   begin
      W.Pending (Pos) := B;
      W.Pending_Count := W.Pending_Count + 1;
   end Enqueue_Pending;

   function Dequeue_Pending
     (W : in out Window)
      return Ada.Streams.Stream_Element
   is
      Result : constant Ada.Streams.Stream_Element := W.Pending (W.Pending_First);
   begin
      W.Pending_First := Pending_Index (Add_Mod (W.Pending_First, 1, Pending_Capacity));
      W.Pending_Count := W.Pending_Count - 1;
      return Result;
   end Dequeue_Pending;

   procedure Emit
     (W : in out Window;
      B : Ada.Streams.Stream_Element)
   is
   begin
      W.History (W.History_Next) := B;
      W.History_Next := History_Index (Add_Mod (W.History_Next, 1, Window_Size));

      if W.History_Count < Window_Size then
         W.History_Count := W.History_Count + 1;
      end if;

      W.Total := W.Total + 1;
      Enqueue_Pending (W, B);
   end Emit;

   procedure Reset
     (W : in out Window)
   is
   begin
      W.History_Next := 0;
      W.History_Count := 0;
      W.Pending_First := 0;
      W.Pending_Count := 0;
      W.Total := 0;
      W.Copy_Remaining := 0;
      W.Copy_Distance := 0;
   end Reset;

   procedure Seed
     (W    : in out Window;
      Data : Ada.Streams.Stream_Element_Array)
   is
      Start : Ada.Streams.Stream_Element_Offset := Data'First;
   begin
      W.History_Next := 0;
      W.History_Count := 0;
      W.Pending_First := 0;
      W.Pending_Count := 0;
      W.Total := 0;
      W.Copy_Remaining := 0;
      W.Copy_Distance := 0;

      if Data'Length > Window_Size then
         Start := Data'Last - Ada.Streams.Stream_Element_Offset (Window_Size) + 1;
      end if;

      for I in Start .. Data'Last loop
         W.History (W.History_Next) := Data (I);
         W.History_Next := History_Index (Add_Mod (W.History_Next, 1, Window_Size));
         if W.History_Count < Window_Size then
            W.History_Count := W.History_Count + 1;
         end if;
      end loop;
   end Seed;

   function Total_Output
     (W : Window)
      return Natural
   is
   begin
      return W.Total;
   end Total_Output;

   function Pending_Output
     (W : Window)
      return Natural
   is
   begin
      return W.Pending_Count;
   end Pending_Output;

   procedure Put_Byte
     (W      : in out Window;
      B      : Ada.Streams.Stream_Element;
      Status : out Write_Status)
   is
   begin
      if W.Pending_Count = Pending_Capacity then
         Status := Need_Output;
         return;
      end if;

      Emit (W, B);
      Status := Ok;
   end Put_Byte;

   procedure Begin_Copy
     (W        : in out Window;
      Length   : Natural;
      Distance : Natural;
      Status   : out Write_Status)
   is
   begin
      if Length < 3 or else Length > 258 then
         Status := Invalid_Length;
         return;
      end if;

      pragma Assert (Length in 3 .. 258, "LZ77 copy length out of range");
      pragma Assert (Distance <= 32_768, "LZ77 copy distance exceeds Deflate window");

      if Distance = 0
        or else Distance > Window_Size
        or else Distance > W.History_Count
      then
         Status := Invalid_Distance;
         return;
      end if;

      W.Copy_Remaining := Length;
      W.Copy_Distance := Distance;
      Status := Ok;
   end Begin_Copy;

   procedure Emit_Copy_Byte
     (W      : in out Window;
      B      : out Ada.Streams.Stream_Element;
      Status : out Write_Status)
   is
   begin
      if W.Copy_Remaining = 0 then
         B := 0;
         Status := Ok;
         return;
      end if;

      if W.Pending_Count = Pending_Capacity then
         B := 0;
         Status := Need_Output;
         return;
      end if;

      B := W.History (Back_Index (W, W.Copy_Distance));
      Emit (W, B);
      W.Copy_Remaining := W.Copy_Remaining - 1;

      if W.Copy_Remaining = 0 then
         W.Copy_Distance := 0;
      end if;

      Status := Ok;
   end Emit_Copy_Byte;

   procedure Start_Copy
     (W        : in out Window;
      Length   : Natural;
      Distance : Natural;
      Status   : out Write_Status)
   is
   begin
      Begin_Copy (W, Length, Distance, Status);
      if Status = Ok then
         Continue_Copy (W, Status);
      end if;
   end Start_Copy;

   procedure Continue_Copy
     (W      : in out Window;
      Status : out Write_Status)
   is
      B : Ada.Streams.Stream_Element;
   begin
      while W.Copy_Remaining > 0 loop
         Emit_Copy_Byte (W, B, Status);
         if Status /= Ok then
            return;
         end if;
      end loop;

      Status := Ok;
   end Continue_Copy;

   procedure Drain
     (W        : in out Window;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset)
   is
   begin
      Out_Data := [others => 0];
      Out_Last := Before_First (Out_Data);
      Drain_Append (W, Out_Data, Out_Last);
   end Drain;

   procedure Drain_Append
     (W        : in out Window;
      Out_Data : in out Ada.Streams.Stream_Element_Array;
      Out_Last : in out Ada.Streams.Stream_Element_Offset)
   is
      Start : Ada.Streams.Stream_Element_Offset;
   begin
      if Out_Data'Length = 0 then
         Out_Last := Before_First (Out_Data);
         return;
      end if;

      if Out_Last = Before_First (Out_Data) then
         Start := Out_Data'First;
      elsif Out_Last >= Out_Data'Last then
         return;
      else
         Start := Out_Last + 1;
      end if;

      for I in Start .. Out_Data'Last loop
         exit when W.Pending_Count = 0;

         Out_Data (I) := Dequeue_Pending (W);
         Out_Last := I;
      end loop;
   end Drain_Append;

   function Copy_Active
     (W : Window)
      return Boolean
   is
   begin
      return W.Copy_Remaining > 0;
   end Copy_Active;

end Zlib.Sliding_Window;
