#include <ntddk.h>
#include <wdf.h>

// Driver/Device context structure
typedef struct _DEVICE_CONTEXT {
    WDFDEVICE Device;
    BOOLEAN LowPowerMode;
    ULONG CurrentRPM;
    ULONG TargetRPM;
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)

// Function declarations
DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD HddControlDeviceAdd;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL HddControlIoDeviceControl;

// IOCTL codes
#define IOCTL_SET_PERFORMANCE CTL_CODE(FILE_DEVICE_UNKNOWN, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_GET_STATUS CTL_CODE(FILE_DEVICE_UNKNOWN, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)

// Performance levels
typedef enum _PERFORMANCE_LEVEL {
    PERFORMANCE_NORMAL = 0,
    PERFORMANCE_LOW = 1,
    PERFORMANCE_ULTRA_LOW = 2
} PERFORMANCE_LEVEL;

NTSTATUS DriverEntry(
    _In_ PDRIVER_OBJECT DriverObject,
    _In_ PUNICODE_STRING RegistryPath
)
{
    NTSTATUS status;
    WDF_DRIVER_CONFIG config;

    WDF_DRIVER_CONFIG_INIT(&config, HddControlDeviceAdd);

    status = WdfDriverCreate(
        DriverObject,
        RegistryPath,
        WDF_NO_OBJECT_ATTRIBUTES,
        &config,
        WDF_NO_HANDLE
    );

    return status;
}

NTSTATUS HddControlDeviceAdd(
    _In_ WDFDRIVER Driver,
    _Inout_ PWDFDEVICE_INIT DeviceInit
)
{
    NTSTATUS status;
    WDFDEVICE device;
    WDF_OBJECT_ATTRIBUTES deviceAttributes;
    WDF_IO_QUEUE_CONFIG queueConfig;
    PDEVICE_CONTEXT deviceContext;

    UNREFERENCED_PARAMETER(Driver);

    // Create device
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&deviceAttributes, DEVICE_CONTEXT);

    status = WdfDeviceCreate(
        &DeviceInit,
        &deviceAttributes,
        &device
    );

    if (!NT_SUCCESS(status)) {
        return status;
    }

    // Initialize device context
    deviceContext = GetDeviceContext(device);
    deviceContext->Device = device;
    deviceContext->LowPowerMode = FALSE;
    deviceContext->CurrentRPM = 7200; // Default RPM
    deviceContext->TargetRPM = 7200;

    // Create default queue
    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(
        &queueConfig,
        WdfIoQueueDispatchSequential
    );

    queueConfig.EvtIoDeviceControl = HddControlIoDeviceControl;

    status = WdfIoQueueCreate(
        device,
        &queueConfig,
        WDF_NO_OBJECT_ATTRIBUTES,
        WDF_NO_HANDLE
    );

    return status;
}

VOID HddControlIoDeviceControl(
    _In_ WDFQUEUE Queue,
    _In_ WDFREQUEST Request,
    _In_ size_t OutputBufferLength,
    _In_ size_t InputBufferLength,
    _In_ ULONG IoControlCode
)
{
    NTSTATUS status = STATUS_SUCCESS;
    PDEVICE_CONTEXT deviceContext;
    WDFDEVICE device;
    PERFORMANCE_LEVEL performanceLevel;
    size_t bytesReturned = 0;

    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(InputBufferLength);

    device = WdfIoQueueGetDevice(Queue);
    deviceContext = GetDeviceContext(device);

    switch (IoControlCode) {
        case IOCTL_SET_PERFORMANCE:
            // Get performance level from input buffer
            status = WdfRequestRetrieveInputBuffer(
                Request,
                sizeof(PERFORMANCE_LEVEL),
                &performanceLevel,
                NULL
            );

            if (NT_SUCCESS(status)) {
                switch (performanceLevel) {
                    case PERFORMANCE_NORMAL:
                        deviceContext->TargetRPM = 7200;
                        deviceContext->LowPowerMode = FALSE;
                        break;

                    case PERFORMANCE_LOW:
                        deviceContext->TargetRPM = 5400;
                        deviceContext->LowPowerMode = TRUE;
                        break;

                    case PERFORMANCE_ULTRA_LOW:
                        deviceContext->TargetRPM = 4200;
                        deviceContext->LowPowerMode = TRUE;
                        break;

                    default:
                        status = STATUS_INVALID_PARAMETER;
                        break;
                }

                if (NT_SUCCESS(status)) {
                    // Gradually adjust RPM
                    while (deviceContext->CurrentRPM != deviceContext->TargetRPM) {
                        if (deviceContext->CurrentRPM > deviceContext->TargetRPM) {
                            deviceContext->CurrentRPM -= 100;
                        } else {
                            deviceContext->CurrentRPM += 100;
                        }
                        // Add delay to prevent sudden changes
                        KeStallExecutionProcessor(1000);
                    }
                }
            }
            break;

        case IOCTL_GET_STATUS:
            // Return current status
            struct {
                ULONG CurrentRPM;
                BOOLEAN LowPowerMode;
            } status_info;

            status_info.CurrentRPM = deviceContext->CurrentRPM;
            status_info.LowPowerMode = deviceContext->LowPowerMode;

            status = WdfRequestRetrieveOutputBuffer(
                Request,
                sizeof(status_info),
                &status_info,
                &bytesReturned
            );
            break;

        default:
            status = STATUS_INVALID_DEVICE_REQUEST;
            break;
    }

    WdfRequestCompleteWithInformation(Request, status, bytesReturned);
}
