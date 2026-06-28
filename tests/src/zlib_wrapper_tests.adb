with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib;
with Zlib.Wrapper;

package body Zlib_Wrapper_Tests is
   use type Interfaces.Unsigned_32;
   use type Zlib.Status_Code;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Wrapper");
   end Name;

   procedure Test_Parse_Valid_Stored_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Data : constant Zlib.Byte_Array :=
        [1  => 16#78#,
         2  => 16#01#,
         3  => 16#01#,
         4  => 16#00#,
         5  => 16#00#,
         6  => 16#FF#,
         7  => 16#FF#,
         8  => 16#00#,
         9  => 16#00#,
         10 => 16#00#,
         11 => 16#01#];

      Info   : Zlib.Wrapper.Zlib_Stream_Info;
      Status : Zlib.Status_Code;
   begin
      Zlib.Wrapper.Parse (Data, Info, Status);

      Assert (Status = Zlib.Ok, "valid zlib wrapper must parse successfully");

      Assert
        (Info.Deflate_First = 3,
         "Deflate payload must begin after zlib header");

      Assert
        (Info.Deflate_Last = 7,
         "Deflate payload must end before Adler-32 footer");

      Assert
        (Info.Expected_Adler = 16#0000_0001#,
         "Adler-32 footer must be parsed as big-endian");
   end Test_Parse_Valid_Stored_Empty;

   procedure Test_Reject_Too_Short_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Data : constant Zlib.Byte_Array :=
        [1 => 16#78#, 2 => 16#01#, 3 => 16#00#, 4 => 16#01#];

      Info   : Zlib.Wrapper.Zlib_Stream_Info;
      Status : Zlib.Status_Code;
   begin
      Zlib.Wrapper.Parse (Data, Info, Status);

      Assert
        (Status = Zlib.Unexpected_End_Of_Input,
         "zlib input shorter than header plus footer must be rejected");
   end Test_Reject_Too_Short_Input;

   procedure Test_Reject_Invalid_Method
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Data : constant Zlib.Byte_Array :=
        [1 => 16#70#,
         2 => 16#07#,
         3 => 16#00#,
         4 => 16#00#,
         5 => 16#00#,
         6 => 16#01#];

      Info   : Zlib.Wrapper.Zlib_Stream_Info;
      Status : Zlib.Status_Code;
   begin
      Zlib.Wrapper.Parse (Data, Info, Status);

      Assert
        (Status = Zlib.Unsupported_Method,
         "zlib compression method other than Deflate must be rejected");
   end Test_Reject_Invalid_Method;

   procedure Test_Reject_Invalid_Header_Check
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Data : constant Zlib.Byte_Array :=
        [1 => 16#78#,
         2 => 16#02#,
         3 => 16#00#,
         4 => 16#00#,
         5 => 16#00#,
         6 => 16#01#];

      Info   : Zlib.Wrapper.Zlib_Stream_Info;
      Status : Zlib.Status_Code;
   begin
      Zlib.Wrapper.Parse (Data, Info, Status);

      Assert
        (Status = Zlib.Invalid_Header,
         "zlib CMF/FLG value not divisible by 31 must be rejected");
   end Test_Reject_Invalid_Header_Check;

   procedure Test_Reject_Preset_Dictionary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Data : constant Zlib.Byte_Array :=
        [1 => 16#78#,
         2 => 16#20#,
         3 => 16#00#,
         4 => 16#00#,
         5 => 16#00#,
         6 => 16#01#];

      Info   : Zlib.Wrapper.Zlib_Stream_Info;
      Status : Zlib.Status_Code;
   begin
      Zlib.Wrapper.Parse (Data, Info, Status);

      Assert
        (Status = Zlib.Unsupported_Preset_Dictionary,
         "zlib preset dictionary streams must be rejected");
   end Test_Reject_Preset_Dictionary;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Parse_Valid_Stored_Empty'Access, "Parse valid zlib wrapper");

      Registration.Register_Routine
        (T, Test_Reject_Too_Short_Input'Access, "Reject too-short zlib input");

      Registration.Register_Routine
        (T,
         Test_Reject_Invalid_Method'Access,
         "Reject invalid compression method");

      Registration.Register_Routine
        (T,
         Test_Reject_Invalid_Header_Check'Access,
         "Reject invalid zlib header check");

      Registration.Register_Routine
        (T, Test_Reject_Preset_Dictionary'Access, "Reject preset dictionary");
   end Register_Tests;

end Zlib_Wrapper_Tests;
