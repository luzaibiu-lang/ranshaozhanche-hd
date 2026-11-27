using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

// This launcher only updates verified release files and starts the native game.
// Gameplay, login, rooms, AI and rendering all live in the Godot/Go source.
internal static class Launcher
{
    internal static readonly string Origin = ReadOrigin();
    internal static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
    private static string ReadOrigin()
    {
        try {
            var values=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"connection.json"),Encoding.UTF8));
            var uri=new Uri(Convert.ToString(values["endpoint"]));
            if((uri.Scheme=="https"&&String.IsNullOrEmpty(uri.UserInfo)&&uri.AbsolutePath=="/"&&String.IsNullOrEmpty(uri.Query)&&String.IsNullOrEmpty(uri.Fragment))||(uri.Scheme=="http"&&uri.IsLoopback))return uri.GetLeftPart(UriPartial.Authority);
        } catch {} return "http://127.0.0.1:18180";
    }
    [STAThread] private static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        try
        {
            string certificate = Path.Combine(Root, "hd-public.crt");
            byte[] expected = File.Exists(certificate) ? new X509Certificate2(certificate).GetRawCertData() : null;
            ServicePointManager.ServerCertificateValidationCallback = (sender, cert, chain, errors) =>
            {
                var request = sender as HttpWebRequest;
                if (errors == SslPolicyErrors.None) return true;
                if (expected == null || request == null || request.RequestUri.Authority != new Uri(Origin).Authority || cert == null) return false;
                if ((errors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0) return false;
                byte[] actual = cert.GetRawCertData();
                if (actual.Length != expected.Length) return false;
                int difference = 0; for (int i=0;i<actual.Length;i++) difference |= actual[i]^expected[i];
                return difference == 0;
            };
            if (args.Length == 1 && args[0] == "--verify-update")
            {
                var updater = new Updater(null);
                int changed = updater.Execute();
                Console.WriteLine("verified_update_files="+changed);
                return 0;
            }
            foreach(string arg in args)if(arg.StartsWith("--wait-game=")){
                int id;if(Int32.TryParse(arg.Substring(12),out id))try{using(var previous=Process.GetProcessById(id))if(String.Equals(previous.MainModule.FileName,Path.Combine(Root,"Game.exe"),StringComparison.OrdinalIgnoreCase))previous.WaitForExit(10000);}catch(ArgumentException){}
            }
            foreach (var process in Process.GetProcessesByName("Game"))
            {
                try { if (String.Equals(process.MainModule.FileName,Path.Combine(Root,"Game.exe"),StringComparison.OrdinalIgnoreCase)) return 0; }
                catch (System.ComponentModel.Win32Exception) {}
                finally { process.Dispose(); }
            }
            bool existed;
            using (var mutex = new Mutex(true, "Local\\BurningChariotHD_" + Hash(Encoding.UTF8.GetBytes(Root)).Substring(0,20)+"_"+Path.GetFileNameWithoutExtension(Application.ExecutablePath), out existed))
            {
                if (!existed) return 0;
                string host=Path.Combine(Root,"LauncherHost.exe");
                if(!String.Equals(Path.GetFileNameWithoutExtension(Application.ExecutablePath),"LauncherHost",StringComparison.OrdinalIgnoreCase)&&File.Exists(host)){
                    string boot=Guid.NewGuid().ToString("N");
                    using(var child=Process.Start(new ProcessStartInfo(host,"--bootstrap-id="+boot){WorkingDirectory=Root,UseShellExecute=false})){
                        child.WaitForExit();
                        if(child.ExitCode==37){
                            string request=BootstrapRequest(boot);
                            string ticket=File.ReadAllText(request,Encoding.ASCII).Trim();File.Delete(request);
                            Guid parsed;if(!Guid.TryParseExact(ticket,"N",out parsed))throw new IOException("启动请求无效");
                            return RunUpdate(null,parsed==Guid.Empty ? null : ticket);
                        }
                        return child.ExitCode;
                    }
                } else {
                    string boot="";foreach(string arg in args)if(arg.StartsWith("--bootstrap-id=")){Guid parsed;if(Guid.TryParseExact(arg.Substring(15),"N",out parsed))boot=parsed.ToString("N");}
                    return RunUpdate(boot,null);
                }
            }
        }
        catch (Exception e) { if(args.Length==1 && args[0]=="--verify-update")Console.Error.WriteLine(e.Message);else MessageBox.Show("启动失败："+e.Message,"燃烧战车",MessageBoxButtons.OK,MessageBoxIcon.Error); return 1; }
    }
    internal static string Hash(byte[] data) { using (var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "").ToLowerInvariant(); }
    internal static string BootstrapRequest(string boot)
    {
        string local=Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(local,"BurningChariotHD","bootstrap-"+boot+".txt");
    }
    private static int RunUpdate(string boot,string ticket)
    {
        using(var window=new UpdateWindow(boot,ticket)) { Application.Run(window);return window.Result; }
    }
    internal static string HashFile(string path) { using(var sha=SHA256.Create()) using(var input=File.OpenRead(path)) return BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "").ToLowerInvariant(); }
    internal static void StartGame(string ticket)
    {
        if (!File.Exists(Path.Combine(Root,"Game.exe")) || !File.Exists(Path.Combine(Root,"Game.pck"))) throw new IOException("游戏文件不完整，请重新解压完整客户端。");
        string engine="",options=String.IsNullOrEmpty(ticket) ? "" : "--launcher-ticket="+ticket;
        if(new Uri(Origin).IsLoopback&&Environment.GetEnvironmentVariable("BCHD_QA_SILENT")=="1"){
            engine="--audio-driver Dummy ";string proof=Environment.GetEnvironmentVariable("BCHD_QA_PROOF");
            if(!String.IsNullOrEmpty(proof))options+=" \"--qa-proof="+proof+"\"";
        }
        Process.Start(new ProcessStartInfo(Path.Combine(Root,"Game.exe"),engine+"-- "+options) { WorkingDirectory=Root,UseShellExecute=false });
    }
}

internal sealed class UpdateWindow : Form
{
    private readonly Label note = new Label();
    private readonly ProgressBar bar = new ProgressBar();
    private bool working=true;
    private readonly string boot;
    private readonly string ticket;
    internal int Result=1;
    internal UpdateWindow(string bootstrapId,string sessionTicket)
    {
        boot=bootstrapId;ticket=sessionTicket;
        Text="燃烧战车 · 检查更新";ClientSize=new Size(540,140);StartPosition=FormStartPosition.CenterScreen;
        FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;MinimizeBox=false;
        Font=new Font("Microsoft YaHei UI",10);BackColor=Color.FromArgb(185,190,200);ForeColor=Color.FromArgb(25,43,65);
        note.SetBounds(24,22,490,55);note.Text="正在检查游戏文件…";Controls.Add(note);
        bar.SetBounds(24,88,490,20);bar.Style=ProgressBarStyle.Marquee;Controls.Add(bar);
        Shown += (s,e) => ThreadPool.QueueUserWorkItem(_ => Work());
        FormClosing += (s,e) => { if(working) e.Cancel=true; };
    }
    private void Report(string text) { if(!IsDisposed) BeginInvoke((Action)(()=>note.Text=text)); }
    private void Work()
    {
        try
        {
            bool runningHost=String.Equals(Path.GetFileName(Application.ExecutablePath),"LauncherHost.exe",StringComparison.OrdinalIgnoreCase);
            if(new Updater(Report).Execute(runningHost)==Updater.HostUpdateRequired)
            {
                if(String.IsNullOrEmpty(boot))throw new IOException("请从燃烧战车.exe 重新打开以更新游戏。");
                // A 0.1.x parent expects a 32-digit ticket. An empty GUID means in-game login.
                string request=Launcher.BootstrapRequest(boot);
                Directory.CreateDirectory(Path.GetDirectoryName(request));
                File.WriteAllText(request,Guid.Empty.ToString("N"),Encoding.ASCII);
                Result=37;
            }
            else
            {
                Launcher.StartGame(ticket);
                Result=0;
            }
            BeginInvoke((Action)(()=> { working=false;Close(); }));
        }
        catch(Exception error)
        {
            BeginInvoke((Action)(()=>{
                working=false;note.Text="更新未完成："+error.Message;bar.Style=ProgressBarStyle.Blocks;
                var retry=new Button {Text="重试",Left=350,Top=96,Width=75};
                var close=new Button {Text="关闭",Left=435,Top=96,Width=75};close.Click+=(s,e)=>Close();Controls.Add(close);
                retry.Click+=(s,e)=>{retry.Dispose();close.Dispose();working=true;bar.Style=ProgressBarStyle.Marquee;note.Text="正在检查游戏文件…";ThreadPool.QueueUserWorkItem(_=>Work());};Controls.Add(retry);
            }));
        }
    }
}

internal sealed class ReleaseFile { public string path {get;set;} public long size {get;set;} public string sha256 {get;set;} public string url {get;set;} }
internal sealed class ReleaseManifest { public string version {get;set;} public string edition {get;set;} public List<ReleaseFile> files {get;set;} }
internal sealed class TransactionFile { public string path {get;set;} public bool existed {get;set;} }
internal sealed class Updater
{
    private readonly Action<string> report;
    private string workDirectory;
    private bool cleanStaging=true;
    internal Updater(Action<string> report) { this.report=report ?? (_=>{}); }
    internal const int HostUpdateRequired=-1;
    private static HttpWebRequest Request(string path)
    {
        var r=(HttpWebRequest)WebRequest.Create(Launcher.Origin+path);r.Proxy=null;r.Timeout=20000;r.ReadWriteTimeout=30000;r.UserAgent="BurningChariotHD";r.AllowAutoRedirect=false;return r;
    }
    private static string Target(string relative)
    {
        if(String.IsNullOrEmpty(relative) || relative.IndexOf('\\')>=0 || relative.StartsWith("/") || relative.Contains(":") || relative.Contains("..") || relative.StartsWith(".")) throw new IOException("更新文件路径无效");
        foreach(char c in relative) if(!(Char.IsLetterOrDigit(c) || c=='/' || c=='_' || c=='-' || c=='.' || c==' ')) throw new IOException("更新文件名无效");
        string full=Path.GetFullPath(Path.Combine(Launcher.Root,relative.Replace('/',Path.DirectorySeparatorChar)));
        if(!full.StartsWith(Launcher.Root,StringComparison.OrdinalIgnoreCase)) throw new IOException("更新路径越界");
        return full;
    }
    internal int Execute(bool runningHost=false)
    {
        string root=Path.Combine(Launcher.Root,".update");
        if(Directory.Exists(root)) foreach(string candidate in Directory.GetDirectories(root))
        {
            Guid id;
            if(!Guid.TryParseExact(Path.GetFileName(candidate),"N",out id))continue;
            Recover(candidate);
            Directory.Delete(candidate,true);
        }
        try {return ExecuteCore(runningHost);}
        finally {if(cleanStaging && workDirectory!=null && Directory.Exists(workDirectory)) Directory.Delete(workDirectory,true);}
    }
    private static void Recover(string staging)
    {
        string journal=Path.Combine(staging,"transaction.json");
        if(!File.Exists(journal) || File.Exists(Path.Combine(staging,"complete")))return;
        var entries=new JavaScriptSerializer().Deserialize<List<TransactionFile>>(File.ReadAllText(journal,Encoding.UTF8));
        if(entries==null || entries.Count>1000)throw new IOException("更新恢复记录无效");
        entries.Reverse();
        foreach(var entry in entries)
        {
            string target=Target(entry.path),old=Path.Combine(staging,"old",entry.path.Replace('/',Path.DirectorySeparatorChar)),pending=Path.Combine(staging,"new",entry.path.Replace('/',Path.DirectorySeparatorChar));
            if(File.Exists(old)) {if(File.Exists(target))File.Delete(target);File.Move(old,target);}
            else if(!entry.existed && !File.Exists(pending) && File.Exists(target))File.Delete(target);
        }
    }
    private int ExecuteCore(bool runningHost)
    {
        ReleaseManifest manifest;
        using(var response=Request("/updates/manifest.json").GetResponse())
        using(var input=response.GetResponseStream())
        using(var output=new MemoryStream())
        {
            var buffer=new byte[8192];int n;while((n=input.Read(buffer,0,buffer.Length))>0) {output.Write(buffer,0,n);if(output.Length>1024*1024)throw new IOException("更新清单过大");}
            manifest=new JavaScriptSerializer().Deserialize<ReleaseManifest>(Encoding.UTF8.GetString(output.ToArray()));
        }
        if(manifest==null || manifest.edition!="hd" || manifest.files==null || manifest.files.Count>1000) throw new IOException("更新清单无效");
        string staging=Path.Combine(Launcher.Root,".update",Guid.NewGuid().ToString("N"));
        workDirectory=staging;
        var changes=new List<ReleaseFile>();var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var file in manifest.files)
        {
            string target=Target(file.path);
            if(!seen.Add(file.path) || file.size<0 || file.size>512*1024*1024 || file.sha256==null || file.sha256.Length!=64) throw new IOException("更新清单文件无效");
            if(file.url!=null && file.url!="blobs/"+file.sha256)throw new IOException("更新地址无效");
            if(!File.Exists(target) || new FileInfo(target).Length!=file.size || Launcher.HashFile(target)!=file.sha256) changes.Add(file);
        }
        if(!seen.Contains("LauncherHost.exe"))throw new IOException("服务器尚未提供完整更新清单，请稍后重试。");
        if(runningHost && changes.Exists(file=>String.Equals(file.path,"LauncherHost.exe",StringComparison.OrdinalIgnoreCase)))return HostUpdateRequired;
        if(changes.Count==0) {RememberManifest(manifest);report("已是最新版本");return 0;}
        foreach(var file in changes)
        {
            report("下载 "+file.path+"\n"+(changes.IndexOf(file)+1)+" / "+changes.Count);
            string pending=Path.Combine(staging,"new",file.path.Replace('/',Path.DirectorySeparatorChar));Directory.CreateDirectory(Path.GetDirectoryName(pending));
            using(var response=Request("/updates/"+(file.url ?? file.path)).GetResponse())
            using(var input=response.GetResponseStream())
            using(var output=File.Create(pending))
            {
                var buffer=new byte[128*1024];int n;long total=0;
                while((n=input.Read(buffer,0,buffer.Length))>0) {total+=n;if(total>file.size)throw new IOException("下载大小超出清单");output.Write(buffer,0,n);}
                if(total!=file.size)throw new IOException("下载未完成，请重试");
            }
            if(Launcher.HashFile(pending)!=file.sha256)throw new IOException("文件校验失败，请重试");
        }
        report("正在应用更新…");
        var journal=new List<TransactionFile>();foreach(var file in changes)journal.Add(new TransactionFile{path=file.path,existed=File.Exists(Target(file.path))});
        string record=Path.Combine(staging,"transaction.json");
        using(var output=new FileStream(record,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {byte[] text=Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(journal));output.Write(text,0,text.Length);output.Flush(true);}
        cleanStaging=false;
        try
        {
            foreach(var file in changes)
            {
                string target=Target(file.path),backup=Path.Combine(staging,"old",file.path.Replace('/',Path.DirectorySeparatorChar)),pending=Path.Combine(staging,"new",file.path.Replace('/',Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(target));Directory.CreateDirectory(Path.GetDirectoryName(backup));
                if(File.Exists(target))File.Move(target,backup);
                File.Move(pending,target);
            }
        }
        catch
        {
            Recover(staging);cleanStaging=true;throw;
        }
        // Only this invocation's generated staging tree is removed. Old or
        // unrelated client/user files are never swept by the updater.
        File.WriteAllText(Path.Combine(staging,"complete"),"ok",Encoding.ASCII);
        cleanStaging=true;RememberManifest(manifest);return changes.Count;
    }
    private static void RememberManifest(ReleaseManifest manifest)
    {
        string path=Path.Combine(Launcher.Root,"manifest.json");
        if(File.Exists(path))
        {
            ReleaseManifest previous=null;
            try {previous=new JavaScriptSerializer().Deserialize<ReleaseManifest>(File.ReadAllText(path,Encoding.UTF8));}catch(ArgumentException){}
            if(previous!=null && previous.edition=="hd" && previous.files!=null && previous.files.Count<=1000)
            {
                var current=new HashSet<string>(StringComparer.OrdinalIgnoreCase);foreach(var file in manifest.files)current.Add(file.path);
                foreach(var file in previous.files)
                {
                    if(current.Contains(file.path))continue;
                    string retired=Target(file.path);
                    if(File.Exists(retired) && Launcher.HashFile(retired)==file.sha256)File.Delete(retired);
                }
            }
        }
        string text=new JavaScriptSerializer().Serialize(manifest);
        if(File.Exists(path) && File.ReadAllText(path,Encoding.UTF8)==text)return;
        string temporary=path+".pending";
        using(var file=new FileStream(temporary,FileMode.Create,FileAccess.Write,FileShare.None)) {byte[] bytes=Encoding.UTF8.GetBytes(text);file.Write(bytes,0,bytes.Length);file.Flush(true);}
        if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);
    }
}
