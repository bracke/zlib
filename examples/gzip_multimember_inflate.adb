with Ada.Command_Line;
with Ada.Text_IO;
with Zlib; use Zlib;

procedure GZip_Multimember_Inflate is
   use type Zlib.Status_Code;

   First_Input : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('o')),
      2 => Zlib.Byte (Character'Pos ('n')),
      3 => Zlib.Byte (Character'Pos ('e'))];

   Second_Input : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('t')),
      2 => Zlib.Byte (Character'Pos ('w')),
      3 => Zlib.Byte (Character'Pos ('o'))];

   Status : Zlib.Status_Code;
begin
   declare
      First_Member : constant Zlib.Byte_Array :=
        Zlib.GZip (First_Input, Zlib.Auto, Status);
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line ("first gzip member failed: " & Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Second_Member : constant Zlib.Byte_Array :=
           Zlib.GZip (Second_Input, Zlib.Auto, Status);
      begin
         if Status /= Zlib.Ok then
            Ada.Text_IO.Put_Line ("second gzip member failed: " & Zlib.Status_Image (Status));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            Combined : constant Zlib.Byte_Array := First_Member & Second_Member;
            Expected : constant Zlib.Byte_Array := First_Input & Second_Input;
            Decoded  : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header
                (Combined, Zlib.GZip, Zlib.Multi_Member, Status);
         begin
            if Status /= Zlib.Ok or else Decoded /= Expected then
               Ada.Text_IO.Put_Line ("multi-member gzip inflate failed: " & Zlib.Status_Image (Status));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
         end;
      end;
   end;

   Ada.Text_IO.Put_Line ("gzip multi-member inflate ok");
end GZip_Multimember_Inflate;
