#pragma once
#include <stdint.h>

enum class State : uint8_t {
    SLEEP,
    SCANNING,
    CONNECTING,
    AUTHENTICATING,
    UNLOCKED
};

// Called once from setup()
void sm_init();

// Called every loop() iteration — drives all state transitions
void sm_update();

// External trigger: button ISR sets this flag
extern volatile bool g_button_pressed;
