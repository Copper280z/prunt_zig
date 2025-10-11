-----------------------------------------------------------------------------
--                                                                         --
--                   Part of the Prunt Motion Controller                   --
--                                                                         --
--            Copyright (C) 2024 Liam Powell (liam@prunt3d.com)            --
--                                                                         --
--  This program is free software: you can redistribute it and/or modify   --
--  it under the terms of the GNU General Public License as published by   --
--  the Free Software Foundation, either version 3 of the License, or      --
--  (at your option) any later version.                                    --
--                                                                         --
--  This program is distributed in the hope that it will be useful,        --
--  but WITHOUT ANY WARRANTY; without even the implied warranty of         --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          --
--  GNU General Public License for more details.                           --
--                                                                         --
--  You should have received a copy of the GNU General Public License      --
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.  --
--                                                                         --
-----------------------------------------------------------------------------

with Prunt;                   use Prunt;
with Prunt.Controller;
--  with System.Multiprocessors;
--  with Ada.Text_IO;             use Ada.Text_IO;
with Prunt.Controller_Generic_Types;
with Prunt.TMC_Types.TMC2240; use Prunt.TMC_Types.TMC2240;
with Prunt.TMC_Types;         use Prunt.TMC_Types;
with Ada.Streams;
--  with Interfaces.C;

procedure Prunt_Simulator is

   --  package Dimensionless_Text_IO is new Ada.Text_IO.Float_IO (Dimensionless);

   type Stepper_Name is new Axis_Name;

   type Heater_Name is (Hotend, Bed);

   type Fan_Name is (Fan_1, Fan_2);

   type Board_Temperature_Probe_Name is (Hotend, Bed);

   type Empty_Enum is new Boolean range True .. False;
   
   package My_Controller_Generic_Types is new
     Prunt.Controller_Generic_Types
       (Stepper_Name                 => Stepper_Name,
        Heater_Name                  => Heater_Name,
        Thermistor_Name              => Heater_Name,
        Board_Temperature_Probe_Name => Board_Temperature_Probe_Name,
        Fan_Name                     => Fan_Name,
        Input_Switch_Name            => Stepper_Name,
        Laser_Name                   => Empty_Enum);

   use My_Controller_Generic_Types;

   procedure Setup
     (Heater_Thermistors : Heater_Thermistor_Map;
      Thermistors        : Thermistor_Parameters_Array_Type)
   is null;
   procedure Reconfigure_Heater
     (Heater : Heater_Name; Params : Prunt.Heater_Parameters)
   is null;
   procedure Reconfigure_Fan (Fan : Fan_Name; PWM_Freq : Fan_PWM_Frequency)
   is null;
   procedure Autotune_Heater
     (Heater : Heater_Name; Params : Prunt.Heater_Parameters)
   is null;
   procedure Setup_For_Loop_Move (Switch : Stepper_Name; Hit_State : Pin_State)
   is null;
   procedure Setup_For_Conditional_Move
     (Switch : Stepper_Name; Hit_State : Pin_State)
   is null;
   procedure Reset_Position (Pos : Stepper_Position) is null;
   procedure Wait_Until_Idle (Last_Command : Command_Index) is null;

   procedure Enqueue_Command (Command : Queued_Command);

   function StepperToCInt (Stepper : Stepper_Name) return Integer is
   begin
      case Stepper is
         when X_Axis =>
            return 0;

         when Y_Axis =>
            return 1;

         when Z_Axis =>
            return 2;

         when E_Axis =>
            return 3;
      end case;
   end StepperToCInt;

   --  Import the C function (not passed directly to Prunt)
   procedure Enable_Stepper_C (Stepper : Integer);
   pragma Import (C, Enable_Stepper_C, "enable_stepper");

   procedure Disable_Stepper_C (Stepper : Integer);
   pragma Import (C, Disable_Stepper_C, "disable_stepper");

   procedure Enqueue_Command_C
     (X, Y, Z, E : Long_Float; Index : Integer; Safe_Stop : Integer);
   pragma Import (C, Enqueue_Command_C, "enqueue_command");

   procedure Configure_C (Interpolation_Time : Float);
   pragma Import (C, Configure_C, "configure");

   procedure Shutdown_C;
   pragma Import (C, Shutdown_C, "shutdown");

   --  Ada wrapper with the correct convention and type
   procedure Enable_Stepper (Stepper : Stepper_Name) is
   begin
      Enable_Stepper_C (StepperToCInt (Stepper));
   end Enable_Stepper;

   procedure Disable_Stepper (Stepper : Stepper_Name) is
   begin
      Disable_Stepper_C (StepperToCInt (Stepper));
   end Disable_Stepper;

   procedure Reset is
   begin
      Shutdown_C;
   end Reset;

   function Get_Extra_HTTP_Content (Name : String) return access constant Ada.Streams.Stream_Element_Array is
   begin
      return null;
   end Get_Extra_HTTP_Content;


   function Get_Board_Specific_Documentation (Name : String) return String is
   --  Stepper_Text : String := "";
   --  EndStop_Text : String := "";
   begin
   return "";
   end Get_Board_Specific_Documentation;

   Max_Fan_Frequency  : constant Frequency := 25_000.0 * hertz;

   package My_Controller is new
     Prunt.Controller
      (Generic_Types              => My_Controller_Generic_Types,
         Stepper_Hardware           =>
          [others =>
             (Kind            => Basic_Kind,
              Enable_Stepper  => Enable_Stepper'Access,
              Disable_Stepper => Disable_Stepper'Access,
              Maximum_Delta_Per_Command => Dimensionless(10_000) )],
         --  Heater_Hardware            => null,
         Fan_Hardware               => [others =>
             (Kind                            => Fixed_Switching_Kind,
              Reconfigure_Fixed_Switching_Fan => Reconfigure_Fan'Access,
              Maximum_PWM_Frequency           => Max_Fan_Frequency)],
         Interpolation_Time         => 0.000_1 * s,
         Loop_Interpolation_Time    => 0.000_1 * s,
         Setup                      => Setup,
         Reconfigure_Heater         => Reconfigure_Heater,
         Autotune_Heater            => Autotune_Heater,
         Setup_For_Loop_Move        => Setup_For_Loop_Move,
         Setup_For_Conditional_Move => Setup_For_Conditional_Move,
         Enqueue_Command            => Enqueue_Command,
         Reset_Position             => Reset_Position,
         Wait_Until_Idle            => Wait_Until_Idle,
         Reset                      => Reset,
         Get_Extra_HTTP_Content     => Get_Extra_HTTP_Content,
         Get_Board_Specific_Documentation    => Get_Board_Specific_Documentation,
         Update_Check         => (Method => None),
         Config_Path                => "./prunt_sim.json");

   procedure Enqueue_Command (Command : Queued_Command) is
      --  Should use double precision here for best numerical stability with high order derivatives
      X_Pos : constant Long_Float := Long_Float (Command.Pos (X_Axis) / mm);
      Y_Pos : constant Long_Float := Long_Float (Command.Pos (Y_Axis) / mm);
      Z_Pos : constant Long_Float := Long_Float (Command.Pos (Z_Axis) / mm);
      E_Pos : constant Long_Float := Long_Float (Command.Pos (E_Axis) / mm);
      Index : constant Integer := Integer (Command.Index);
      Safe  : constant Integer := (if Command.Safe_Stop_After then 1 else 0);

   begin
      Enqueue_Command_C (X_Pos, Y_Pos, Z_Pos, E_Pos, Index, Safe);
      My_Controller.Report_Last_Command_Executed (Command.Index);
   end Enqueue_Command;

begin
   Configure_C (0.000_1);
   My_Controller.Run;
end Prunt_Simulator;
