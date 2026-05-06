// Copyright 2026 Fondazione Chips-IT, ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Riccardo Fiorani Gallotta <riccardo.fiorani3@unibo.it>
//         Andrea Di Ruzza <andrea.diruzza@chips.it>
//
// Behaviour model of generic io pads
//
// When implementing tech cell wrappers do not change the default parameter value
// and put assertions to check the correct values.
// 
// All inputs are expected to be active high. If a physical cell input is active 
// low invert it inside the wrapper. The only exception is the internal retention 
// enable signal (the LSB of internal signals) which polarity can be controlled with
// the configuration struct.
<%
from typing import Any, Dict, List, Literal, Optional, Set, Annotated
from pydantic import BaseModel, Field, ConfigDict, model_validator

# Configuration parameters
PullUpDownMode = Literal[
    "pud_en/pud_sel",
    "pu_en/pd_en/bus_hold",
    "pu_en/pd_en/1_hot",
    "pu only",
    "pd only"
]

OutputControlMode = Literal[
    "output enable",
    "tristate enable"
]

Orientation = Literal[
    "horizontal",
    "vertical"
]

InternalSignals = Literal[
    "bias",
    "retention_enabled",
    "pwr_ok_core",
    "pwr_ok_io",
]

InputStageMode = Literal[
    "always_on",       # input_stage=True, input_enable=False
    "with_enable_pin"  # input_stage=True, input_enable=True
]

# Configuration bits: None = feature not present, int >= 1 = number of configuration bits
ConfigBits = Annotated[int, Field(ge=1, description="Number of configuration bits (>= 1)")]


MODULE_BASE_NAME = "tc_pad"


class PadType(BaseModel):
  model_config = ConfigDict(extra="forbid", frozen=True)

  # --- Internal signals ---
  internal_signals: Optional[Set[InternalSignals]] = None

  # --- Retention ---
  retention_control: bool = False
  retention_on_inputs: bool = False

  # --- Input stage ---
  input_stage: Optional[InputStageMode] = None
  schmitt_trigger: bool = False

  # --- Pull up/down ---
  pull_mode: Optional[PullUpDownMode] = None

  # --- NAND tree (test) ---
  nand_tree: bool = False

  # --- Output stage ---
  output_stage: bool = False
  output_control: Optional[OutputControlMode] = None
  slew_rate_control: Optional[ConfigBits] = None
  drive_strength_control: Optional[ConfigBits] = None

  # --- Physical ---
  orientation: Optional[Orientation] = None

  @model_validator(mode="after")
  def check_input_dependencies(self) -> "PadType":
    if self.schmitt_trigger and self.input_stage is None:
      raise ValueError(
        "`schmitt_trigger` requires `input_stage` to be set."
      )
    return self

  @model_validator(mode="after")
  def check_output_dependencies(self) -> "PadType":
    output_only_fields = {
      "output_control": self.output_control,
      "slew_rate_control": self.slew_rate_control,
      "drive_strength_control": self.drive_strength_control,
    }
    if not self.output_stage:
      active = [k for k, v in output_only_fields.items() if v is not None]
      if active:
        raise ValueError(
          f"Fields {active} require `output_stage=True`."
        )
    return self

  @model_validator(mode="after")
  def check_retention_dependencies(self) -> "PadType":
    if self.retention_on_inputs and not self.retention_control:
      raise ValueError(
        "`retention_on_inputs` requires `retention_control=True`."
      )
    return self

  @model_validator(mode="after")
  def check_nand_tree(self) -> "PadType":
    if self.nand_tree and self.input_stage is None and not self.output_stage:
      raise ValueError(
        "`nand_tree` requires at least `input_stage` or `output_stage`."
      )
    return self

  pad_types = {}
  pad_types["pwr_mng"] = PadType(common=True, retention_control=True)
  pad_types["pad_corner"] = PadType(common=True)
  for orientation in ["horizontal", "vertical"]:
    {pad_types[f"{supply}_{domain}_{orientation[0]}"] = PadType(common=True, orientation=orientation) \
      for supply in ["vdd", "vss"] for domain in ["core", "io"]}
    {pad_types[f"bidir_{orientation[0]}"] = PadType(
      common=True, input_stage=True, input_enable=True, schmitt_trigger=True, pull_mode="pu_en/pd_en/bus_hold", retention_on_inputs=True, 
      nand_tree=True, output_stage=True, output_control="tristate enable", slew_rate_control=True, drive_strength_control=True)}
    {pad_types[f"input_{orientation[0]}"] = PadType(
      common=True, input_stage=True, input_enable=True, schmitt_trigger=True, pull_mode="pu_en/pd_en/bus_hold", retention_on_inputs=True)}
    {pad_types[f"output_{orientation[0]}"] = PadType(
      common=True, retention_on_inputs=True, 
      nand_tree=True, output_stage=True, output_control="tristate enable", slew_rate_control=True, drive_strength_control=True)}
%>\
<%def name="pad_name(phy, pin, chip, bit)">\
hyper_${phy}_${pin}${f"_{chip}" if chip!="" else ""}${f"_b{bit}" if bit!="" else ""}\
</%def>\
<%def name="hyp_name(phy, pin, chip, bit)">\
hyper_${pin}[${phy.removeprefix("phy")}]${[chip] if chip!="" else ""}${[bit] if bit!="" else ""}\
</%def>\
<%def name="pad_conn(phy, pin, chip, bit)">\
pad_hyper_${phy}_${pin}${f"_{chip}" if chip!="" else ""}${f"_b{bit}" if bit!="" else ""}_pad\
</%def>\

% for name, v in pad_types.items():
module ${MODULE_BASE_NAME}_${name} (
  % if v.common:
    inout 
    input  logic [${m.pad_width-1}:0] ${m.pad_name}_pad,
    output logic [${m.pad_width-1}:0] ${m.pad_name}_hyp
);

endmodule
% endfor
