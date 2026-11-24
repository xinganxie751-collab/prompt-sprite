using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace PromptSprite
{
    public sealed class RegionRecorder : IDisposable
    {
        private readonly BinaryWriter writer;
        private readonly Rectangle bounds;
        private readonly Bitmap bitmap;
        private readonly Graphics graphics;
        private readonly MemoryStream jpeg = new MemoryStream();
        private readonly List<uint[]> index = new List<uint[]>();
        private long riffSize, movieSize, mainCount, streamCount;
        private bool disposed;
        public int FrameCount { get { return index.Count; } }
        public bool HasVisibleContent { get; private set; }

        [DllImport("user32.dll")]
        public static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);

        [DllImport("user32.dll")]
        public static extern bool UnregisterHotKey(IntPtr window, int id);

        public RegionRecorder(string path, Rectangle region, int fps)
        {
            bounds = region;
            bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format24bppRgb);
            graphics = Graphics.FromImage(bitmap);
            writer = new BinaryWriter(File.Create(path));
            Four("RIFF");
            riffSize = Placeholder();
            Four("AVI ");
            long header = List("hdrl");
            Chunk("avih", 56);
            writer.Write(1000000 / fps);
            writer.Write(0); writer.Write(0); writer.Write(0x10);
            mainCount = Placeholder();
            writer.Write(0); writer.Write(1); writer.Write(0);
            writer.Write(bounds.Width); writer.Write(bounds.Height);
            for (int i = 0; i < 4; i++) writer.Write(0);

            long stream = List("strl");
            Chunk("strh", 56);
            Four("vids"); Four("MJPG");
            writer.Write(0); writer.Write(0); writer.Write(0);
            writer.Write(1); writer.Write(fps); writer.Write(0);
            streamCount = Placeholder();
            writer.Write(0); writer.Write(-1); writer.Write(0);
            writer.Write((short)0); writer.Write((short)0);
            writer.Write((short)bounds.Width); writer.Write((short)bounds.Height);
            Chunk("strf", 40);
            writer.Write(40); writer.Write(bounds.Width); writer.Write(bounds.Height);
            writer.Write((short)1); writer.Write((short)24);
            Four("MJPG");
            writer.Write(bounds.Width * bounds.Height * 3);
            for (int i = 0; i < 4; i++) writer.Write(0);
            FinishList(stream);
            FinishList(header);
            movieSize = List("movi");
        }

        private void Four(string value) { writer.Write(Encoding.ASCII.GetBytes(value)); }
        private long Position { get { return writer.BaseStream.Position; } }
        private long Placeholder() { long p = Position; writer.Write(0); return p; }
        private void Patch(long offset, long value)
        {
            long end = Position;
            writer.BaseStream.Position = offset;
            writer.Write(checked((uint)value));
            writer.BaseStream.Position = end;
        }
        private long List(string kind) { Four("LIST"); long size = Placeholder(); Four(kind); return size; }
        private void FinishList(long size) { Patch(size, Position - size - 4); }
        private void Chunk(string kind, int size) { Four(kind); writer.Write(size); }

        public void Capture()
        {
            graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
            if (!HasVisibleContent)
            {
                for (int y = 0; y < bitmap.Height && !HasVisibleContent; y += Math.Max(1, bitmap.Height / 20))
                    for (int x = 0; x < bitmap.Width && !HasVisibleContent; x += Math.Max(1, bitmap.Width / 20))
                    {
                        Color pixel = bitmap.GetPixel(x, y);
                        HasVisibleContent = Math.Max(pixel.R, Math.Max(pixel.G, pixel.B)) > 24;
                    }
            }
            jpeg.SetLength(0);
            bitmap.Save(jpeg, ImageFormat.Jpeg);
            int length = checked((int)jpeg.Length);
            index.Add(new[] { checked((uint)(Position - movieSize - 4)), (uint)length });
            Chunk("00dc", length);
            writer.Write(jpeg.GetBuffer(), 0, length);
            if ((length & 1) != 0) writer.Write((byte)0);
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            try
            {
                FinishList(movieSize);
                Chunk("idx1", index.Count * 16);
                foreach (uint[] entry in index)
                {
                    Four("00dc"); writer.Write(0x10); writer.Write(entry[0]); writer.Write(entry[1]);
                }
                Patch(mainCount, index.Count);
                Patch(streamCount, index.Count);
                Patch(riffSize, Position - 8);
            }
            finally
            {
                writer.Dispose();
                jpeg.Dispose();
                graphics.Dispose();
                bitmap.Dispose();
            }
        }
    }
}
