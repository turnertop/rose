using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.Versioning;
using Rose.Core;

namespace Rose.Imaging;

/// Windows' GDI+ codecs provide a fallback for formats such as TIFF that Skia does not decode.
/// This class is never called on macOS/Linux; the common codec path remains SkiaSharp.
[SupportedOSPlatform("windows")]
internal static class WindowsImageDecoder
{
    public static ImageMetadata? Metadata(string path)
    {
        try
        {
            using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var image = Image.FromStream(stream, true, false);
            var rotated = Orientation(image) >= 5;
            return new(rotated ? image.Height : image.Width, rotated ? image.Width : image.Height);
        }
        catch (Exception e) when (e is ArgumentException or IOException or OutOfMemoryException or System.Runtime.InteropServices.ExternalException) { return null; }
    }
    public static byte[] Decode(string path, int maximumEdge, CancellationToken cancellation)
    {
        using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var image = Image.FromStream(stream, true, false);
        if ((long)image.Width * image.Height > ImageDecoder.MaximumDecodeBytes / 4)
            throw new InvalidDataException("This image exceeds the preview decoder's memory limit.");
        cancellation.ThrowIfCancellationRequested();
        var transform = Orientation(image) switch
        {
            2 => RotateFlipType.RotateNoneFlipX, 3 => RotateFlipType.Rotate180FlipNone,
            4 => RotateFlipType.Rotate180FlipX, 5 => RotateFlipType.Rotate90FlipX,
            6 => RotateFlipType.Rotate90FlipNone, 7 => RotateFlipType.Rotate270FlipX,
            8 => RotateFlipType.Rotate270FlipNone, _ => RotateFlipType.RotateNoneFlipNone
        };
        image.RotateFlip(transform);
        var scale = Math.Min(1d, (double)maximumEdge / Math.Max(image.Width, image.Height));
        using var result = new Bitmap(Math.Max(1, (int)Math.Round(image.Width * scale)), Math.Max(1, (int)Math.Round(image.Height * scale)), PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(result))
        {
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.CompositingMode = CompositingMode.SourceCopy;
            graphics.DrawImage(image, new Rectangle(0, 0, result.Width, result.Height), 0, 0, image.Width, image.Height, GraphicsUnit.Pixel);
        }
        cancellation.ThrowIfCancellationRequested(); using var output = new MemoryStream(); result.Save(output, ImageFormat.Png); return output.ToArray();
    }
    private static int Orientation(Image image)
    {
        try { return image.GetPropertyItem(0x112)?.Value is { Length: >= 2 } value ? BitConverter.ToUInt16(value, 0) : 1; }
        catch (ArgumentException) { return 1; }
    }
}
