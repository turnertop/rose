using Avalonia.Input.Platform;
using Avalonia.Media.Imaging;
using Rose.Imaging;

namespace Rose.Desktop;

/// Keeps clipboard pixels alive independently of the viewer's disposable preview.
public sealed class ImageClipboard : IDisposable
{
    private readonly SemaphoreSlim _gate = new(1);
    private CancellationTokenSource? _request;
    private Bitmap? _bitmap;
    private bool _disposed;

    public async Task CopyAsync(string path, IClipboard clipboard)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _request?.Cancel();
        using var request = new CancellationTokenSource();
        _request = request;
        var token = request.Token;
        var entered = false;
        Bitmap? decoded = null;
        try
        {
            await _gate.WaitAsync(token); entered = true;
            decoded = await Task.Run(() =>
            {
                var data = ImageDecoder.Decode(path, int.MaxValue, token);
                return new Bitmap(new MemoryStream(data, false));
            }, token);
            token.ThrowIfCancellationRequested();
            await clipboard.SetBitmapAsync(decoded);
            var previous = _bitmap; _bitmap = decoded; decoded = null;
            previous?.Dispose();
            // Windows retains the copied pixels after Rose closes.
            await clipboard.FlushAsync();
        }
        finally
        {
            decoded?.Dispose();
            if (entered)
            {
                if (_disposed) { _bitmap?.Dispose(); _bitmap = null; }
                _gate.Release();
            }
            if (ReferenceEquals(_request, request)) _request = null;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true; _request?.Cancel();
        if (_gate.CurrentCount != 0) { _bitmap?.Dispose(); _bitmap = null; }
    }
}
