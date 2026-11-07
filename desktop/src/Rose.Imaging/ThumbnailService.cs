using System.Security.Cryptography;
using System.Text;
using Rose.Core;

namespace Rose.Imaging;

public sealed class ThumbnailService : IDisposable
{
    private sealed class Job
    {
        public readonly CancellationTokenSource Cancellation = new();
        public Task<byte[]> Task = null!;
        public int Subscribers;
    }
    private readonly Dictionary<string, Job> _jobs = [];
    private readonly SemaphoreSlim _decoders;
    private readonly Func<string, int, CancellationToken, byte[]> _decode;
    private readonly string _directory;
    private readonly long _diskBudget;
    private int _trimming; private int _writes; private bool _disposed;
    public int PendingCount { get { lock (_jobs) return _jobs.Count; } }
    public ThumbnailService(string directory, int concurrency = 2, long diskBudget = 512L * 1024 * 1024,
        Func<string, int, CancellationToken, byte[]>? decode = null)
    {
        _directory = directory; _decoders = new(concurrency); _diskBudget = diskBudget; _decode = decode ?? ImageDecoder.Decode;
        Directory.CreateDirectory(directory); TrimInBackground();
    }
    public static int Bucket(double edge) => edge <= 128 ? 128 : edge <= 256 ? 256 : edge <= 512 ? 512 : 1024;
    public static string Key(ImageAsset asset, int edge) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
        $"v1|{asset.Path}|{asset.ByteSize}|{asset.ModifiedUtc.Ticks}|{edge}")));
    public async Task<byte[]> RequestAsync(ImageAsset asset, int edge, CancellationToken cancellation = default)
    {
        cancellation.ThrowIfCancellationRequested();
        var key = Key(asset, edge); Job job;
        lock (_jobs)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (!_jobs.TryGetValue(key, out job!))
            {
                job = new(); var captured = job;
                job.Task = Task.Run(() => LoadAsync(asset, edge, key, captured.Cancellation.Token));
                _jobs[key] = job;
            }
            job.Subscribers++;
        }
        try { return await job.Task.WaitAsync(cancellation); }
        finally
        {
            lock (_jobs)
            {
                if (--job.Subscribers == 0)
                {
                    _jobs.Remove(key);
                    if (!job.Task.IsCompleted) job.Cancellation.Cancel();
                    _ = job.Task.ContinueWith(task => { _ = task.Exception; job.Cancellation.Dispose(); }, TaskScheduler.Default);
                }
            }
        }
    }
    private async Task<byte[]> LoadAsync(ImageAsset asset, int edge, string key, CancellationToken cancellation)
    {
        await _decoders.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            cancellation.ThrowIfCancellationRequested();
            var file = new FileInfo(asset.Path);
            if (!file.Exists) throw new FileNotFoundException("The original image is unavailable.", asset.Path);
            if (file.Length != asset.ByteSize || file.LastWriteTimeUtc != asset.ModifiedUtc) throw new IOException("The image changed; refreshing its metadata.");
            var cached = Path.Combine(_directory, key + ".png");
            try
            {
                if (File.Exists(cached))
                {
                    var data = await File.ReadAllBytesAsync(cached, cancellation).ConfigureAwait(false);
                    if (data.Length >= 20 && data[0] == 137 && data[1] == 80 && data[2] == 78 && data[3] == 71 &&
                        data.AsSpan(data.Length - 12).SequenceEqual(new byte[] { 0,0,0,0,73,69,78,68,174,66,96,130 })) return data;
                    File.Delete(cached);
                }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            var result = _decode(asset.Path, edge, cancellation);
            cancellation.ThrowIfCancellationRequested();
            file.Refresh();
            if (!file.Exists || file.Length != asset.ByteSize || file.LastWriteTimeUtc != asset.ModifiedUtc) throw new IOException("The image changed while its thumbnail was loading.");
            var temporary = cached + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try { await File.WriteAllBytesAsync(temporary, result, cancellation).ConfigureAwait(false); File.Move(temporary, cached, true); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { /* Cache failures never hide the decoded image. */ }
            finally { try { if (File.Exists(temporary)) File.Delete(temporary); } catch (IOException) { } }
            if (Interlocked.Increment(ref _writes) % 32 == 0) TrimInBackground();
            return result;
        }
        finally { _decoders.Release(); }
    }
    private void TrimInBackground()
    {
        if (Interlocked.CompareExchange(ref _trimming, 1, 0) != 0) return;
        _ = Task.Run(() =>
        {
            try
            {
                var files = new DirectoryInfo(_directory).GetFiles("*.png").Where(x => x.Name.Length == 68).OrderBy(x => x.LastWriteTimeUtc).ToArray();
                var bytes = files.Sum(x => x.Length);
                if (bytes <= _diskBudget) return;
                foreach (var file in files) { try { var length = file.Length; file.Delete(); bytes -= length; } catch (IOException) { } if (bytes <= _diskBudget * .75) break; }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            finally { Interlocked.Exchange(ref _trimming, 0); }
        });
    }
    public void Dispose()
    {
        lock (_jobs) { if (_disposed) return; _disposed = true; foreach (var job in _jobs.Values) job.Cancellation.Cancel(); }
        // Jobs own their cancellation sources; active native decodes finish before their subscription releases.
    }
}
