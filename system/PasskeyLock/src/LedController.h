#pragma once

typedef enum {
    LED_INITIALIZING,  // Red solid              — boot / self-test
    LED_AP_MODE,       // Red blinking           — WiFi provisioning AP active
    LED_READY,         // Yellow solid           — idle, awaiting button press
    LED_SEARCHING,     // Yellow blinking        — BLE scan in progress
    LED_FOUND,         // Yellow solid + Green blinking — target found, authenticating
    LED_AUTH_PASS,     // Green solid            — HMAC verified
    LED_AUTH_FAIL,     // Red blinking + Yellow solid   — HMAC mismatch
    LED_ENGAGED        // Green solid            — relay energised / locked
} LedPattern;

void led_init();
void led_set(LedPattern pattern);
void led_update();  // call every loop() iteration; handles all blink timing
