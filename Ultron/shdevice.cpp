#include <windows.h>
#include <stdio.h>

#define IOCTL_SET_PERFORMANCE CTL_CODE(FILE_DEVICE_UNKNOWN, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_GET_STATUS CTL_CODE(FILE_DEVICE_UNKNOWN, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)

typedef enum _PERFORMANCE_LEVEL {
    PERFORMANCE_NORMAL = 0,
    PERFORMANCE_LOW = 1,
    PERFORMANCE_ULTRA_LOW = 2
} PERFORMANCE_LEVEL;

int main()
{
    HANDLE hDevice;
    DWORD bytesReturned;
    PERFORMANCE_LEVEL level;

    // Open device
    hDevice = CreateFile(
        L"\\\\.\\HddControl",
        GENERIC_READ | GENERIC_WRITE,
        0,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL
    );

    if (hDevice == INVALID_HANDLE_VALUE) {
        printf("Failed to open device\n");
        return 1;
    }

    // Set to low performance mode
    level = PERFORMANCE_LOW;
    if (!DeviceIoControl(
        hDevice,
        IOCTL_SET_PERFORMANCE,
        &level,
        sizeof(level),
        NULL,
        0,
        &bytesReturned,
        NULL
    )) {
        printf("Failed to set performance level\n");
    }

    // Get status
    struct {
        ULONG CurrentRPM;
        BOOLEAN LowPowerMode;
    } status;

    if (DeviceIoControl(
        hDevice,
        IOCTL_GET_STATUS,
        NULL,
        0,
        &status,
        sizeof(status),
        &bytesReturned,
        NULL
    )) {
        printf("Current RPM: %d\n", status.CurrentRPM);
        printf("Low Power Mode: %s\n", status.LowPowerMode ? "Yes" : "No");
    }

    CloseHandle(hDevice);
    return 0;
}
