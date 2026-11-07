using Rose.Core;
using SkiaSharp;

namespace Rose.Imaging;

public static class ImageDecoder
{
    public const long MaximumDecodeBytes = 128L * 1024 * 1024;
    public static ImageMetadata? Metadata(string path)
    {
        try
        {
            using var codec = SKCodec.Create(path);
            if (codec is null) return OperatingSystem.IsWindows() ? WindowsImageDecoder.Metadata(path) : null;
            var rotated = (int)codec.EncodedOrigin >= 5;
            return new(rotated ? codec.Info.Height : codec.Info.Width, rotated ? codec.Info.Width : codec.Info.Height);
        }
        catch (Exception e) when (e is IOException or ArgumentException or UnauthorizedAccessException) { return null; }
    }
    public static byte[] Decode(string path, int maximumEdge, CancellationToken cancellation = default)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumEdge);
        using var codec = SKCodec.Create(path);
        if (codec is null)
        {
            if (OperatingSystem.IsWindows()) return WindowsImageDecoder.Decode(path, maximumEdge, cancellation);
            throw new InvalidDataException("This image format is not supported by the decoder.");
        }
        cancellation.ThrowIfCancellationRequested();
        var size = codec.GetScaledDimensions(Math.Min(1f, (float)maximumEdge / Math.Max(codec.Info.Width, codec.Info.Height)));
        if (size.Width <= 0 || size.Height <= 0 || (long)size.Width * size.Height > MaximumDecodeBytes / 4)
            throw new InvalidDataException("This image exceeds the preview decoder's memory limit.");
        using var colorSpace = SKColorSpace.CreateSrgb();
        var info = new SKImageInfo(size.Width, size.Height, SKColorType.Rgba8888, SKAlphaType.Premul, colorSpace);
        using var bitmap = new SKBitmap(info);
        var result = codec.GetPixels(info, bitmap.GetPixels());
        if (result != SKCodecResult.Success) throw new InvalidDataException("The image could not be decoded (" + result + ").");
        cancellation.ThrowIfCancellationRequested();
        return EncodeOriented(bitmap, codec.EncodedOrigin, maximumEdge);
    }
    internal static byte[] EncodeOriented(SKBitmap bitmap, SKEncodedOrigin origin, int maximumEdge)
    {
        var rotated = (int)origin >= 5;
        var width = rotated ? bitmap.Height : bitmap.Width; var height = rotated ? bitmap.Width : bitmap.Height;
        var scale = Math.Min(1d, (double)maximumEdge / Math.Max(width, height));
        var outputWidth = Math.Max(1, (int)Math.Round(width * scale)); var outputHeight = Math.Max(1, (int)Math.Round(height * scale));
        using var colorSpace = SKColorSpace.CreateSrgb();
        using var output = new SKBitmap(new SKImageInfo(outputWidth, outputHeight, SKColorType.Rgba8888, SKAlphaType.Premul, colorSpace));
        using var canvas = new SKCanvas(output); canvas.Clear(SKColors.Transparent);
        var w = bitmap.Width; var h = bitmap.Height;
        (float a, float b, float c, float d, float tx, float ty) = origin switch
        {
            SKEncodedOrigin.TopRight => (-1, 0, 0, 1, w, 0),
            SKEncodedOrigin.BottomRight => (-1, 0, 0, -1, w, h),
            SKEncodedOrigin.BottomLeft => (1, 0, 0, -1, 0, h),
            SKEncodedOrigin.LeftTop => (0, 1, 1, 0, 0, 0),
            SKEncodedOrigin.RightTop => (0, -1, 1, 0, h, 0),
            SKEncodedOrigin.RightBottom => (0, -1, -1, 0, h, w),
            SKEncodedOrigin.LeftBottom => (0, 1, -1, 0, 0, w),
            _ => (1, 0, 0, 1, 0, 0)
        };
        var sx = (float)outputWidth / width; var sy = (float)outputHeight / height;
        canvas.SetMatrix(new SKMatrix { ScaleX = a * sx, SkewX = b * sx, TransX = tx * sx, SkewY = c * sy, ScaleY = d * sy, TransY = ty * sy, Persp2 = 1 });
        using var source = SKImage.FromBitmap(bitmap);
        canvas.DrawImage(source, 0, 0, new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.Linear));
        using var image = SKImage.FromBitmap(output);
        using var data = image.Encode(SKEncodedImageFormat.Png, 90);
        return data.ToArray();
    }
}

/// Keeps one composited GIF frame in memory. No array of decoded animation frames is retained.
public sealed class GifPlayback : IDisposable
{
    private readonly SKCodec _codec;
    private readonly SKBitmap _bitmap;
    private readonly SKCodecFrameInfo[] _frames;
    private int _next; private int _loop; private bool _disposed;
    private GifPlayback(SKCodec codec)
    {
        _codec = codec; _frames = codec.FrameInfo;
        _bitmap = new(new SKImageInfo(codec.Info.Width, codec.Info.Height, SKColorType.Rgba8888, SKAlphaType.Premul));
    }
    public static GifPlayback? Open(string path)
    {
        var codec = SKCodec.Create(path);
        if (codec is null) return null;
        if (codec.FrameCount < 2 || (long)codec.Info.Width * codec.Info.Height > ImageDecoder.MaximumDecodeBytes / 4) { codec.Dispose(); return null; }
        return new(codec);
    }
    public (byte[] Data, int Delay)? Next()
    {
        lock (this)
        {
            if (_disposed || (_codec.RepetitionCount >= 0 && _loop > _codec.RepetitionCount)) return null;
            if (_next == 0) _bitmap.Erase(SKColors.Transparent);
            var options = new SKCodecOptions(_next, _next == 0 ? -1 : _next - 1);
            if (_codec.GetPixels(_bitmap.Info, _bitmap.GetPixels(), options) != SKCodecResult.Success) return null;
            var result = (ImageDecoder.EncodeOriented(_bitmap, _codec.EncodedOrigin, 4096), Math.Max(20, _frames[_next].Duration));
            _next++; if (_next == _frames.Length) { _next = 0; _loop++; }
            return result;
        }
    }
    public void Dispose() { lock (this) { if (_disposed) return; _disposed = true; _bitmap.Dispose(); _codec.Dispose(); } }
}
