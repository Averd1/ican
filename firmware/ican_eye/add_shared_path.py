Import("env")

# Add the shared directory to the global compiler include path
# so that both src/ and lib/ components can find ble_protocol.h
env.Append(CPPPATH=[
    env.get("PROJECT_DIR") + "/../../shared"
])
