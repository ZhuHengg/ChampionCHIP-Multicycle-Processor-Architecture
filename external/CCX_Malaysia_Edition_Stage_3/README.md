# ChampionCHIP eXperience — Stage 3

Welcome to **Stage 3 of the ChampionCHIP eXperience!** 🚀

> **⚠️ Important — AWS FPGA**
>
> For this part of Stage 3, **you do not need to run your project on the AWS FPGA**.
>
> AWS FPGA access will be required **later only for the 10 best teams**, after the classification results are announced. For now, focus on the activities and instructions provided in this repository.

This repository contains the resources and instructions you will need during this stage.

The repository is divided into **three main folders**. Each folder contains its own **README** with detailed instructions. Please read the README inside each folder before starting.

## 📁 1. Official Test Firmware

**Folder:** `1-RVBL-GPIO-UART-Test-Firmware`

This folder contains the **official Stage 3 test firmware** for GPIO and UART and the files required to work with it.

Inside the folder, you will find a dedicated README explaining the firmware, its structure, and how it should be used during the challenge.

➡️ **Start here and read the README before using the firmware.**

---

## 📁 2. RVBL Firmware Builder

**Folder:** `2-RVBL-Firmware-Builder`

This folder contains the **Makefile and instructions for generating your own RISC-V firmware**.

The README will guide you through the process of using the provided Makefile to compile your **RISC-V assembly code** and generate the firmware file required for your processor.

➡️ **Read the README and follow the steps to generate your firmware.**

---

## 📁 3. RVBL Emulator

**Folder:** `3-RVBL-Emulator`

This folder contains the resources for the **RVBL Emulator Application**.

The emulator will be introduced **later in Stage 3** and will allow you to interact with and test your RISC-V processor in a more complete application environment.

The README inside this folder will provide the instructions for setting up and using the emulator when we reach this part of Stage 3.

➡️ **Instructions for the RVBL Emulator will be provided later in Stage 3.**

---

## 🚀 Repository Structure

```text
Stage-3/
│
├── 1-RVBL-GPIO-UART-Test-Firmware/
│   ├── README.md
│   └── ...
│
├── 2-RVBL-Firmware-Builder/
│   ├── README.md
│   ├── Makefile
│   └── ...
│
├── 3-RVBL-Emulator/
│   ├── README.md
│   └── ...
│
└── README.md
```