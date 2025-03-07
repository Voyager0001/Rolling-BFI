#include <windows.h>
#include <D3dkmthk.h>
#include <chrono>
using namespace std::chrono;
const char g_szClassName[] = "RollingBFIwindowClass";
bool quitProgram = false;
int scanPosition = 0;
int scanHeight = 0;
int screenHeight = 0;
int skipFrames = 0;  // Used to skip frames to ensure even brightness

// Window event handling
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg)
    {
    case WM_CLOSE:
        quitProgram = true;
        DestroyWindow(hwnd);
        break;
    case WM_DESTROY:
        quitProgram = true;
        PostQuitMessage(0);
        break;
    default:
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }
    return 0;
}

// For the top black region
LRESULT CALLBACK TopWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg)
    {
    case WM_PAINT:
    {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        RECT rect;
        GetClientRect(hwnd, &rect);
        FillRect(hdc, &rect, (HBRUSH)GetStockObject(BLACK_BRUSH));
        EndPaint(hwnd, &ps);
        return 0;
    }
    // Let mouse messages pass through
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    default:
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }
}

// For the bottom black region
LRESULT CALLBACK BottomWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg)
    {
    case WM_PAINT:
    {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        RECT rect;
        GetClientRect(hwnd, &rect);
        FillRect(hdc, &rect, (HBRUSH)GetStockObject(BLACK_BRUSH));
        EndPaint(hwnd, &ps);
        return 0;
    }
    // Let mouse messages pass through
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    default:
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance,
    LPSTR lpCmdLine, int nCmdShow)
{
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
    WNDCLASSEX wc;
    HWND mainHwnd;
    HWND topHwnd;     // For the black area above the visible strip
    HWND bottomHwnd;  // For the black area below the visible strip
    MSG Msg;

    // Get screen dimensions
    screenHeight = GetSystemMetrics(SM_CYSCREEN);
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);

    // Calculate scan bar height (adjust as needed)
    scanHeight = screenHeight / 4;

    // Calculate step size to ensure even coverage
    // We want to make sure the scan doesn't always hit the same positions
    int stepSize = scanHeight / 3;  // Use a step size that's not a simple divisor of scanHeight

    // Registering the Main Window Class
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.style = 0;
    wc.lpfnWndProc = WndProc;
    wc.cbClsExtra = 0;
    wc.cbWndExtra = 0;
    wc.hInstance = hInstance;
    wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = NULL; // No background
    wc.lpszMenuName = NULL;
    wc.lpszClassName = g_szClassName;
    wc.hIconSm = LoadIcon(NULL, IDI_APPLICATION);

    if (!RegisterClassEx(&wc))
    {
        MessageBox(NULL, "Window Registration Failed!", "Error!",
            MB_ICONEXCLAMATION | MB_OK);
        return 0;
    }

    // Register the top black window class
    wc.lpfnWndProc = TopWndProc;
    wc.lpszClassName = "TopBlackClass";

    if (!RegisterClassEx(&wc))
    {
        MessageBox(NULL, "Top Black Window Registration Failed!", "Error!",
            MB_ICONEXCLAMATION | MB_OK);
        return 0;
    }

    // Register the bottom black window class
    wc.lpfnWndProc = BottomWndProc;
    wc.lpszClassName = "BottomBlackClass";

    if (!RegisterClassEx(&wc))
    {
        MessageBox(NULL, "Bottom Black Window Registration Failed!", "Error!",
            MB_ICONEXCLAMATION | MB_OK);
        return 0;
    }

    // Create main invisible window (for messages/control)
    mainHwnd = CreateWindowEx(
        0,
        g_szClassName,
        "RollingBFI",
        WS_OVERLAPPED,
        0, 0, 1, 1,  // Minimal size as it's just for control
        NULL, NULL, hInstance, NULL);

    if (mainHwnd == NULL)
    {
        MessageBox(NULL, "Main Window Creation Failed!", "Error!",
            MB_ICONEXCLAMATION | MB_OK);
        return 0;
    }

    // Create the top black window - with transparent flag for mouse clicks
    topHwnd = CreateWindowEx(
        WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TRANSPARENT,
        "TopBlackClass",
        NULL,
        WS_POPUP,
        0, 0, screenWidth, screenHeight,  // Initially full screen
        NULL, NULL, hInstance, NULL);

    if (topHwnd == NULL)
    {
        MessageBox(NULL, "Top Black Window Creation Failed!", "Error!",
            MB_ICONEXCLAMATION | MB_OK);
        return 0;
    }

    // Create the bottom black window - with transparent flag for mouse clicks
    bottomHwnd = CreateWindowEx(
        WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TRANSPARENT,
        "BottomBlackClass",
        NULL,
        WS_POPUP,
        0, 0, screenWidth, 0,  // Initially no height (will be adjusted)
        NULL, NULL, hInstance, NULL);

    if (bottomHwnd == NULL)
    {
        MessageBox(NULL, "Bottom Black Window Creation Failed!", "Error!",
            MB_ICONEXCLAMATION | MB_OK);
        return 0;
    }

    // Make both black windows fully opaque
    SetLayeredWindowAttributes(topHwnd, 0, 255, LWA_ALPHA);
    SetLayeredWindowAttributes(bottomHwnd, 0, 255, LWA_ALPHA);

    // Show both windows
    ShowWindow(topHwnd, nCmdShow);
    ShowWindow(bottomHwnd, nCmdShow);

    // Setting up to do V-sync
    D3DKMT_WAITFORVERTICALBLANKEVENT we;
    D3DKMT_OPENADAPTERFROMHDC oa;
    oa.hDc = GetDC(mainHwnd);
    NTSTATUS result = D3DKMTOpenAdapterFromHdc(&oa);

    if (result == STATUS_INVALID_PARAMETER) {
        MessageBox(NULL, "D3DKMTOpenAdapterFromHdc function received an invalid parameter.", "Error!",
            MB_ICONEXCLAMATION | MB_OK);
        return 0;
    }
    else if (result == STATUS_NO_MEMORY) {
        MessageBox(NULL, "D3DKMTOpenAdapterFromHdc function, kernel ran out of memory.", "Error!",
            MB_ICONEXCLAMATION | MB_OK);
        return 0;
    }

    we.hAdapter = oa.hAdapter;
    we.hDevice = 0;
    we.VidPnSourceId = oa.VidPnSourceId;

    // Set up for D3DKTGetScanLine()
    D3DKMT_GETSCANLINE gsl;
    gsl.hAdapter = oa.hAdapter;
    gsl.VidPnSourceId = oa.VidPnSourceId;

    // Main loop
    while (!quitProgram)
    {
        // Wait for vertical blank
        result = D3DKMTWaitForVerticalBlankEvent(&we);

        // Wait for vblank to end
        do {
            high_resolution_clock::time_point pollTime = high_resolution_clock::now() + microseconds(100);
            while (high_resolution_clock::now() < pollTime)
            {
            }
            result = D3DKMTGetScanLine(&gsl);
        } while (gsl.InVerticalBlank == TRUE);

        // Update scan position using the step size to ensure more even distribution
        scanPosition = (scanPosition + stepSize) % screenHeight;

        // Resize and reposition the top and bottom black windows to create a visible strip
        SetWindowPos(topHwnd, HWND_TOPMOST, 0, 0, screenWidth, scanPosition, SWP_SHOWWINDOW);
        SetWindowPos(bottomHwnd, HWND_TOPMOST, 0, scanPosition + scanHeight,
            screenWidth, screenHeight - (scanPosition + scanHeight), SWP_SHOWWINDOW);

        // Process any pending messages
        while (PeekMessage(&Msg, NULL, 0, 0, PM_REMOVE) > 0) {
            TranslateMessage(&Msg);
            DispatchMessage(&Msg);
        }
    }

    return Msg.wParam;
}
