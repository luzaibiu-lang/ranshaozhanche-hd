using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal sealed class LauncherRequestException : IOException
{
    internal readonly int StatusCode;
    internal LauncherRequestException(int statusCode,string message):base(message){StatusCode=statusCode;}
}

internal static class LauncherAccount
{
    internal static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
    internal static string DataRoot { get { return Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BurningChariotHD"); } }
    internal static string VaultRoot { get { return Environment.GetEnvironmentVariable("BCHD_VAULT_ROOT") ?? DataRoot; } }
    internal static readonly byte[] Entropy=Encoding.UTF8.GetBytes("BurningChariotHD.Session.v1");
    internal static Dictionary<string,object> Settings()
    {
        try {return Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(DataRoot,"settings.json"),Encoding.UTF8))??new Dictionary<string,object>();}
        catch {return new Dictionary<string,object>();}
    }
    internal static void Save(string name,bool remember,int width,int height)
    {
        var values=Settings();values["username"]=name;values["remember"]=remember;values["endpoint"]=Launcher.Origin;
        if(width>0)values["window_size"]=new int[]{width,height};else values.Remove("window_size");
        Directory.CreateDirectory(DataRoot);File.WriteAllText(Path.Combine(DataRoot,"settings.json"),Json.Serialize(values),Encoding.UTF8);
    }
    internal static string ReadToken()
    {
        try {
            var settings=Settings();
            if(settings.ContainsKey("endpoint")&&!String.Equals(new Uri(Convert.ToString(settings["endpoint"])).GetLeftPart(UriPartial.Authority),Launcher.Origin,StringComparison.OrdinalIgnoreCase))return "";
            return Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(Path.Combine(VaultRoot,"session.dat")),Entropy,DataProtectionScope.CurrentUser));
        }
        catch {return "";}
    }
    internal static void Remember(string token,bool remember)
    {
        Directory.CreateDirectory(VaultRoot);string path=Path.Combine(VaultRoot,"session.dat");
        if(!remember){if(File.Exists(path))File.Delete(path);return;}
        WriteProtected(path,token);
    }
    internal static Dictionary<string,object> ReadAccount(string name)
    {
        try {
            byte[] plain=ProtectedData.Unprotect(File.ReadAllBytes(Path.Combine(VaultRoot,"account.dat")),Entropy,DataProtectionScope.CurrentUser);
            try {
                var value=Json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(plain));
                if(value!=null&&value.ContainsKey("username")&&value.ContainsKey("password")&&value.ContainsKey("origin")&&
                   String.Equals(Convert.ToString(value["username"]),name,StringComparison.OrdinalIgnoreCase)&&
                   String.Equals(Convert.ToString(value["origin"]),Launcher.Origin,StringComparison.Ordinal))return value;
            } finally {Array.Clear(plain,0,plain.Length);}
        } catch {}
        return new Dictionary<string,object>();
    }
    internal static void RememberAccount(string name,string password,bool remember)
    {
        string path=Path.Combine(VaultRoot,"account.dat");
        if(!remember){if(File.Exists(path))File.Delete(path);return;}
        // An older client may have only a session. Preserve a matching saved
        // password when the current login used that session without typing.
        if(String.IsNullOrEmpty(password)){
            if(ReadAccount(name).Count==0&&File.Exists(path))File.Delete(path);
            return;
        }
        Directory.CreateDirectory(VaultRoot);
        WriteProtected(path,Json.Serialize(new {username=name,password=password,origin=Launcher.Origin}));
    }
    private static void WriteProtected(string path,string value)
    {
        byte[] plain=Encoding.UTF8.GetBytes(value);
        try {
            byte[] bytes=ProtectedData.Protect(plain,Entropy,DataProtectionScope.CurrentUser);
            string temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";File.WriteAllBytes(temporary,bytes);
            if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);
        } finally {Array.Clear(plain,0,plain.Length);}
    }
    internal static string Handoff(string token)
    {
        string folder=Path.Combine(VaultRoot,"handoff");Directory.CreateDirectory(folder);
        foreach(string file in Directory.GetFiles(folder,"*.dat"))if(File.GetLastWriteTimeUtc(file)<DateTime.UtcNow.AddMinutes(-20))File.Delete(file);
        string id=Guid.NewGuid().ToString("N");
        WriteProtected(Path.Combine(folder,id+".dat"),token);return id;
    }
    internal static Dictionary<string,object> Request(string path,object payload,string token)
    {
        var request=(HttpWebRequest)WebRequest.Create(Launcher.Origin+path);request.Proxy=null;request.Timeout=15000;
        request.AutomaticDecompression=DecompressionMethods.GZip|DecompressionMethods.Deflate;
        if(!String.IsNullOrEmpty(token))request.Headers["Authorization"]="Bearer "+token;
        if(payload!=null){request.Method="POST";request.ContentType="application/json; charset=utf-8";byte[] data=Encoding.UTF8.GetBytes(Json.Serialize(payload));using(var stream=request.GetRequestStream())stream.Write(data,0,data.Length);}
        HttpWebResponse response;
        try {response=(HttpWebResponse)request.GetResponse();}
        catch(WebException e){response=e.Response as HttpWebResponse;if(response==null)throw new LauncherRequestException(0,"暂时无法连接游戏服务，请稍后重试。");}
        using(response)using(var reader=new StreamReader(response.GetResponseStream(),Encoding.UTF8)){
            var result=Json.Deserialize<Dictionary<string,object>>(reader.ReadToEnd());
            if((int)response.StatusCode>=400)throw new LauncherRequestException((int)response.StatusCode,result.ContainsKey("error")?Convert.ToString(result["error"]):"操作未完成，请重试。");return result;
        }
    }
}

internal static class LauncherArt
{
    private static readonly Dictionary<string,Bitmap> images=new Dictionary<string,Bitmap>();
    internal static Bitmap Get(string name)
    {
        if(!images.ContainsKey(name))using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("art."+name)){
            if(stream==null)throw new InvalidOperationException("启动器界面资源缺失："+name);
            using(var source=new Bitmap(stream))images[name]=new Bitmap(source);
        }
        return images[name];
    }
    internal static Bitmap Panel()
    {
        if(!images.ContainsKey("login-panel"))images["login-panel"]=Get("title").Clone(new Rectangle(318,104,480,416),System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        return images["login-panel"];
    }
    internal static void Nine(Graphics g,Image image,Rectangle target,int x,int y)
    {
        int[] sx={0,x,image.Width-x,image.Width},sy={0,y,image.Height-y,image.Height};
        int[] dx={target.Left,target.Left+x,target.Right-x,target.Right},dy={target.Top,target.Top+y,target.Bottom-y,target.Bottom};
        for(int a=0;a<3;a++)for(int b=0;b<3;b++)g.DrawImage(image,new Rectangle(dx[a],dy[b],dx[a+1]-dx[a],dy[b+1]-dy[b]),new Rectangle(sx[a],sy[b],sx[a+1]-sx[a],sy[b+1]-sy[b]),GraphicsUnit.Pixel);
    }
    internal static Bitmap Button(bool primary,int state)
    {
        string name=(primary?"start":"button")+state;
        if(!images.ContainsKey(name)){
            Bitmap sheet=Get(primary?"start":"button");int h=sheet.Height/(primary?4:3);
            var frame=sheet.Clone(new Rectangle(0,Math.Min(state,(primary?4:3)-1)*h,sheet.Width,h),System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            for(int y=6;y<h-6;y++)for(int x=14;x<frame.Width-14;x++)frame.SetPixel(x,y,frame.GetPixel(12,y));images[name]=frame;
        }return images[name];
    }
}

internal sealed class MetalButton:Button
{
    internal bool Primary;
    private bool over,pressed;
    internal MetalButton(){SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;Cursor=Cursors.Hand;Font=new Font("Microsoft YaHei UI",12,FontStyle.Bold);}
    protected override void OnMouseEnter(EventArgs e){over=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){over=false;pressed=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnMouseDown(MouseEventArgs e){pressed=true;Invalidate();base.OnMouseDown(e);}
    protected override void OnMouseUp(MouseEventArgs e){pressed=false;Invalidate();base.OnMouseUp(e);}
    protected override void OnPaint(PaintEventArgs e)
    {
        var g=e.Graphics;g.Clear(Parent==null?Color.FromArgb(251,252,254):Parent.BackColor);g.SmoothingMode=SmoothingMode.AntiAlias;
        Color fill=Primary?Color.FromArgb(225,91,39):Color.FromArgb(244,246,249);
        if(Enabled&&over)fill=Primary?Color.FromArgb(241,107,50):Color.FromArgb(232,236,242);
        if(Enabled&&pressed)fill=Primary?Color.FromArgb(195,72,27):Color.FromArgb(219,225,234);
        if(!Enabled)fill=Primary?Color.FromArgb(220,144,111):Color.FromArgb(239,241,245);
        using(var path=new GraphicsPath()){
            int r=Math.Max(4,(int)(6*Font.Size/12));Rectangle b=new Rectangle(1,1,Width-3,Height-3);
            path.AddArc(b.Left,b.Top,r*2,r*2,180,90);path.AddArc(b.Right-r*2,b.Top,r*2,r*2,270,90);
            path.AddArc(b.Right-r*2,b.Bottom-r*2,r*2,r*2,0,90);path.AddArc(b.Left,b.Bottom-r*2,r*2,r*2,90,90);path.CloseFigure();
            using(var brush=new SolidBrush(fill))g.FillPath(brush,path);
            if(!Primary)using(var pen=new Pen(Color.FromArgb(217,223,232)))g.DrawPath(pen,path);
            if(Focused)using(var pen=new Pen(Color.FromArgb(63,115,171),2))g.DrawPath(pen,path);
        }
        TextRenderer.DrawText(g,Text,Font,ClientRectangle,Primary?Color.White:Enabled?Color.FromArgb(46,57,74):Color.FromArgb(119,129,143),TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);
    }
}

internal sealed class LauncherWindow:Form
{
    [DllImport("user32.dll")]private static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]private static extern bool PrintWindow(IntPtr window,IntPtr device,uint flags);
    private const int DesignWidth=920,DesignHeight=620;
    private readonly Dictionary<Control,Rectangle> layout=new Dictionary<Control,Rectangle>();
    private readonly Dictionary<Control,float> fontSizes=new Dictionary<Control,float>();
    private readonly Dictionary<Control,FontStyle> fontStyles=new Dictionary<Control,FontStyle>();
    private float displayScale=1;
    private readonly TextBox username=new TextBox(),password=new TextBox(),confirmation=new TextBox();
    private readonly CheckBox remember=new CheckBox();
    private readonly ComboBox resolution=new ComboBox();
    private readonly MetalButton submit=new MetalButton(),toggle=new MetalButton();
    private readonly Label note=new Label(),confirmLabel=new Label(),optionsLabel=new Label();
    private readonly ProgressBar progress=new ProgressBar();
    private string session="";private bool registering,busy,loading=true,restoringCredentials;private readonly string bootstrap;
    internal int Result;
    static LauncherWindow(){try{SetProcessDPIAware();}catch(EntryPointNotFoundException){}}
    internal LauncherWindow(string bootstrapId,string qaFile)
    {
        bootstrap=bootstrapId;Text="燃烧战车 · 高清重制版";Font=new Font("Microsoft YaHei UI",11);
        AutoScaleMode=AutoScaleMode.None;
        ClientSize=new Size(DesignWidth,DesignHeight);FormBorderStyle=FormBorderStyle.FixedSingle;MaximizeBox=false;StartPosition=FormStartPosition.CenterScreen;
        DoubleBuffered=true;BackColor=Color.FromArgb(251,252,254);
        Icon=System.Drawing.Icon.ExtractAssociatedIcon(Path.Combine(Launcher.Root,"燃烧战车.exe"));
        AddLabel("账号",400,124,120,24);AddLabel("密码",400,198,120,24);
        Field(username,"Username",400,151);Field(password,"Password",400,225);password.UseSystemPasswordChar=true;
        confirmLabel.Text="确认密码";confirmLabel.BackColor=Color.Transparent;confirmLabel.ForeColor=Color.FromArgb(63,73,90);Place(confirmLabel,400,272,150,24,10);
        Field(confirmation,"Confirmation",400,299);confirmation.UseSystemPasswordChar=true;
        optionsLabel.Text="游戏窗口";optionsLabel.BackColor=Color.Transparent;optionsLabel.ForeColor=Color.FromArgb(98,110,128);Place(optionsLabel,584,277,120,21,9);
        remember.Text="记住登录";remember.BackColor=Color.Transparent;remember.ForeColor=Color.FromArgb(63,73,90);remember.Name="Remember";Place(remember,400,305,160,28,10);
        resolution.DropDownStyle=ComboBoxStyle.DropDownList;resolution.Name="Resolution";
        resolution.Items.AddRange(new object[]{"窗口：自动适配屏幕","窗口：1280 × 720","窗口：1600 × 900","窗口：1920 × 1080"});resolution.SelectedIndex=0;Controls.Add(resolution);
        resolution.BackColor=Color.White;resolution.ForeColor=Color.FromArgb(46,57,74);Place(resolution,584,301,272,33,10);
        submit.Name="StartGame";submit.Text="开始游戏";submit.Primary=true;submit.Click+=async(s,e)=>await Start();Place(submit,400,368,456,50,13);
        toggle.Name="ToggleRegistration";toggle.Text="注册账号";toggle.Click+=(s,e)=>{if(!busy){registering=!registering;session="";RefreshMode();if(!registering)RestorePassword();}};Place(toggle,400,432,220,38,10);
        var close=new MetalButton();close.Name="ExitLauncher";close.Text="退出";close.Click+=(s,e)=>Close();Place(close,636,432,220,38,10);
        note.BackColor=Color.Transparent;note.ForeColor=Color.FromArgb(85,102,123);note.TextAlign=ContentAlignment.MiddleLeft;Place(note,400,507,456,56,10);
        progress.Visible=false;Place(progress,400,581,456,5,9);
        username.TabIndex=0;password.TabIndex=1;confirmation.TabIndex=2;remember.TabIndex=3;resolution.TabIndex=4;submit.TabIndex=5;toggle.TabIndex=6;close.TabIndex=7;
        var settings=LauncherAccount.Settings();username.Text=settings.ContainsKey("username")?Convert.ToString(settings["username"]):"";remember.Checked=settings.ContainsKey("remember")&&Convert.ToBoolean(settings["remember"]);
        if(settings.ContainsKey("window_size")){var sizes=settings["window_size"] as System.Collections.IList;if(sizes!=null&&sizes.Count>=2)for(int i=1;i<4;i++)if(Convert.ToInt32(sizes[0])==new int[]{0,1280,1600,1920}[i])resolution.SelectedIndex=i;}
        username.TextChanged+=(s,e)=>{if(!restoringCredentials){session="";password.Clear();}};
        password.TextChanged+=(s,e)=>{if(!restoringCredentials&&password.Text.Length>0)session="";};
        remember.CheckedChanged+=(s,e)=>{
            if(loading||remember.Checked)return;
            try {
                LauncherAccount.Remember("",false);LauncherAccount.RememberAccount("","",false);
                int index=resolution.SelectedIndex;
                LauncherAccount.Save(username.Text.Trim(),false,new int[]{0,1280,1600,1920}[index],new int[]{0,720,900,1080}[index]);
            } catch(Exception){note.Text="无法清除本机登录信息，请检查用户目录权限后重试。";}
        };
        AcceptButton=submit;RefreshMode();FitDisplay();Shown+=async(s,e)=>{
            await LoadSession();
            if(!String.IsNullOrEmpty(qaFile))await VerifyRealControls(qaFile);
        };
    }
    private void Place(Control control,int x,int y,int width,int height,float points)
    {
        if(!Controls.Contains(control))Controls.Add(control);
        layout[control]=new Rectangle(x,y,width,height);fontSizes[control]=points;fontStyles[control]=control is MetalButton?FontStyle.Bold:FontStyle.Regular;
    }
    private void FitDisplay()
    {
        Rectangle area=Screen.FromControl(this).WorkingArea;float dpi;
        using(var graphics=CreateGraphics())dpi=graphics.DpiX/96f;
        float fit=Math.Min((area.Width-32f)/DesignWidth,(area.Height-64f)/DesignHeight);
        ApplyDisplayScale(Math.Max(.5f,Math.Min(dpi,fit)));
    }
    private void ApplyDisplayScale(float scale)
    {
        displayScale=scale;SuspendLayout();ClientSize=new Size((int)Math.Round(DesignWidth*scale),(int)Math.Round(DesignHeight*scale));
        foreach(var entry in layout){Rectangle r=entry.Value;Control control=entry.Key;control.SetBounds((int)Math.Round(r.X*scale),(int)Math.Round(r.Y*scale),(int)Math.Round(r.Width*scale),(int)Math.Round(r.Height*scale));Font previous=control.Font;control.Font=new Font("Microsoft YaHei UI",fontSizes[control]*scale,fontStyles[control]);if(!Object.ReferenceEquals(previous,Font))previous.Dispose();}
        ResumeLayout(false);Invalidate();
    }
    private void AddLabel(string text,int x,int y,int w,int h){var label=new Label();label.Text=text;label.BackColor=Color.Transparent;label.ForeColor=Color.FromArgb(63,73,90);Place(label,x,y,w,h,10);}
    private void Field(TextBox field,string name,int x,int y){field.Name=name;field.Multiline=false;field.BackColor=Color.White;field.ForeColor=Color.FromArgb(30,40,57);field.BorderStyle=BorderStyle.FixedSingle;field.MaxLength=name=="Username"?16:72;Place(field,x,y,456,38,14);}
    private void CaptureClient(string path)
    {
        // PW_CLIENTONLY captures actual child HWNDs without clipping the footer
        // against the non-client title bar, even on the inactive QA desktop.
        using(var image=new Bitmap(ClientSize.Width,ClientSize.Height)){
            using(var graphics=Graphics.FromImage(image)){
                IntPtr device=graphics.GetHdc();bool captured;
                try{captured=PrintWindow(Handle,device,1);}finally{graphics.ReleaseHdc(device);}
                if(!captured)throw new InvalidOperationException("无法读取启动器实际窗口画面");
            }
            image.Save(path);
        }
    }
    private void RefreshMode()
    {
        confirmation.Visible=confirmLabel.Visible=registering;remember.Visible=resolution.Visible=optionsLabel.Visible=!registering;
        submit.Text=registering?"注册并开始游戏":"开始游戏";toggle.Text=registering?"返回登录":"注册账号";note.Text="";
        password.Clear();confirmation.Clear();Invalidate();
    }
    private void Busy(bool value,string message)
    {
        busy=value;submit.Enabled=toggle.Enabled=username.Enabled=password.Enabled=confirmation.Enabled=remember.Enabled=resolution.Enabled=!value;
        submit.Text=value?"请稍候…":registering?"注册并开始游戏":"开始游戏";
        note.Text=message;note.ForeColor=Color.FromArgb(85,102,123);progress.Visible=value;progress.Style=value?ProgressBarStyle.Marquee:ProgressBarStyle.Blocks;
    }
    private void RestorePassword()
    {
        if(registering||!remember.Checked)return;
        var account=LauncherAccount.ReadAccount(username.Text.Trim());
        if(!account.ContainsKey("password"))return;
        restoringCredentials=true;
        try {password.Text=Convert.ToString(account["password"]);}finally{restoringCredentials=false;}
    }
    private async Task LoadSession()
    {
        Busy(true,"正在连接游戏服务…");
        try {
            RestorePassword();
            string saved=remember.Checked?LauncherAccount.ReadToken():"";
            session=saved;
            var state=await Task.Run(()=>LauncherAccount.Request(String.IsNullOrEmpty(saved)?"/health":"/api/state",null,saved));
            if(IsDisposed)return;
            if(!String.IsNullOrEmpty(saved)&&state.ContainsKey("profile")){
                var p=(Dictionary<string,object>)state["profile"];
                string name=Convert.ToString(p["name"]);
                if(!String.Equals(username.Text.Trim(),name,StringComparison.OrdinalIgnoreCase)){username.Text=name;RestorePassword();}
                session=saved;Busy(false,"已记住登录，点击开始游戏。");
            } else Busy(false,password.Text.Length>0?"已记住密码，点击开始游戏。":"服务已连接，准备就绪。");
        } catch(LauncherRequestException error){
            if(!IsDisposed){
                if(error.StatusCode==401){session="";LauncherAccount.Remember("",false);Busy(false,password.Text.Length>0?"登录已过期，已保留密码，点击开始重新登录。":"登录已过期，请重新输入密码。");}
                else Busy(false,"暂时无法连接，已保留登录信息，点击开始重试。");
            }
        } catch(Exception){if(!IsDisposed)Busy(false,"暂时无法连接，已保留登录信息，点击开始重试。");}
        loading=false;
    }
    private async Task Start()
    {
        if(busy||loading)return;
        if(username.Text.Trim().Length==0 || ((registering||session.Length==0)&&password.Text.Length==0)){note.Text="请输入账号和密码。";note.ForeColor=Color.FromArgb(155,34,28);return;}
        if(registering&&password.Text!=confirmation.Text){note.Text="两次输入的密码不一致。";note.ForeColor=Color.FromArgb(155,34,28);return;}
        string name=username.Text.Trim(),plain=password.Text,token=session;bool keep=remember.Checked;bool create=registering;int index=resolution.SelectedIndex;
        Busy(true,create?"正在创建账号…":"正在登录…");
        try {
            if(!create&&token.Length>0){
                try {await Task.Run(()=>LauncherAccount.Request("/api/state",null,token));}
                catch(LauncherRequestException error){
                    if(error.StatusCode!=401)throw;
                    token="";session="";LauncherAccount.Remember("",false);
                    if(plain.Length==0)throw new IOException("登录已过期，请重新输入密码。");
                }
            }
            if(create||token.Length==0){var result=await Task.Run(()=>LauncherAccount.Request(create?"/api/register":"/api/login",new {name=name,password=plain},""));token=Convert.ToString(result["token"]);}
            if(IsDisposed)return;
            // An update failure must retry the authenticated session, rather
            // than submit the completed registration again with empty fields.
            session=token;
            LauncherAccount.RememberAccount(name,plain,keep);LauncherAccount.Remember(token,keep);
            LauncherAccount.Save(name,keep,new int[]{0,1280,1600,1920}[index],new int[]{0,720,900,1080}[index]);
            registering=false;RefreshMode();Busy(true,"正在检查游戏更新…");
            if(!await Task.Run(()=>new Updater(null).HostMatches())){
                if(String.IsNullOrEmpty(bootstrap))throw new IOException("启动器需要更新，请从燃烧战车.exe 重新打开。");
                string bootstrapTicket=LauncherAccount.Handoff(token);
                File.WriteAllText(Path.Combine(LauncherAccount.DataRoot,"bootstrap-"+bootstrap+".txt"),bootstrapTicket,Encoding.ASCII);Result=37;Close();return;
            }
            await Task.Run(()=>new Updater(message=>{if(!IsDisposed)BeginInvoke((Action)(()=>note.Text=message.StartsWith("下载 ")?"正在更新游戏文件…":message));}).Execute());
            if(IsDisposed)return;Launcher.StartGame(LauncherAccount.Handoff(token));Close();
        } catch(Exception e){if(!IsDisposed){Busy(false,e.Message);note.ForeColor=Color.FromArgb(155,34,28);}}
    }
    private async Task VerifyRealControls(string file)
    {
        // Explicit loopback-only test harness. Uses the actual controls,
        // authentication, updater and game process without desktop input.
        var test=LauncherAccount.Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(file,Encoding.UTF8));
        string folder=Convert.ToString(test["output"]);Directory.CreateDirectory(folder);
        string stage=Convert.ToString(test["stage"]);
        if(stage=="appearance"){
            var checks=new List<string>();
            foreach(float scale in new float[]{.8f,1f,1.25f,1.5f,2f}){
                ApplyDisplayScale(scale);
                foreach(bool register in new bool[]{false,true}){
                    registering=register;RefreshMode();note.Text="服务已连接，准备就绪。";
                    foreach(Control control in Controls)if(control.Visible){
                        if(control.Left<0||control.Top<0||control.Right>ClientSize.Width||control.Bottom>ClientSize.Height)throw new InvalidOperationException("启动器控件超出窗口："+control.Name);
                    }
                    if(confirmation.Visible!=registering||confirmLabel.Visible!=registering||remember.Visible==registering||resolution.Visible==registering)throw new InvalidOperationException("注册与登录控件可见性不匹配");
                    if(registering){
                        Rectangle field=confirmation.Bounds;
                        if(field.IntersectsWith(confirmLabel.Bounds)||field.IntersectsWith(submit.Bounds))throw new InvalidOperationException("确认密码控件被遮挡");
                        if(confirmation.Top<password.Bottom)throw new InvalidOperationException("密码与确认密码重叠");
                    }
                    CaptureClient(Path.Combine(folder,"launcher-"+(register?"register":"login")+"-"+scale.ToString("0.00",System.Globalization.CultureInfo.InvariantCulture)+".png"));
                    checks.Add((register?"register":"login")+" scale "+scale+" fits with separate confirmation row");
                }
            }
            ApplyDisplayScale(1f);registering=false;RefreshMode();session="qa-remembered-token";username.Text="qa_visual";session="qa-remembered-token";
            toggle.PerformClick();await Start();
            if(note.Text!="请输入账号和密码。"||busy||session.Length!=0)throw new InvalidOperationException("记住登录后注册跳过了空密码检查");
            checks.Add("registration clears remembered session and rejects empty password without a request");
            password.Text="abc12345";confirmation.Text="different";await Start();
            if(note.Text!="两次输入的密码不一致。"||busy)throw new InvalidOperationException("确认密码校验失败");
            checks.Add("mismatching confirmation remains in launcher with a visible error");
            CaptureClient(Path.Combine(folder,"launcher-register-error.png"));
            Busy(true,"正在检查更新…");
            if(username.Enabled||password.Enabled||confirmation.Enabled||toggle.Enabled||submit.Enabled)throw new InvalidOperationException("连接中仍允许提交");
            CaptureClient(Path.Combine(folder,"launcher-loading.png"));
            checks.Add("authentication and update work disables duplicate submissions");
            Busy(false,"服务已连接，准备就绪。");
            if(!username.Enabled||!password.Enabled||!confirmation.Enabled||!toggle.Enabled||!submit.Enabled)throw new InvalidOperationException("失败后未恢复控件");
            checks.Add("error or completion restores interactive controls");
            // The loopback visual QA endpoint acknowledges authentication but
            // rejects the publication read; no real account or game is created.
            password.Text="qa_visual_password";confirmation.Text=password.Text;remember.Checked=false;await Start();
            if(registering||busy||!submit.Enabled||session.Length==0||password.Text.Length!=0)throw new InvalidOperationException("更新失败后丢失已注册会话或仍显示注册页");
            CaptureClient(Path.Combine(folder,"launcher-authenticated-update-error.png"));
            await Start();
            if(busy||!submit.Enabled||session.Length==0)throw new InvalidOperationException("更新失败后无法直接重试");
            string tickets=Path.Combine(LauncherAccount.VaultRoot,"handoff");
            if(Directory.Exists(tickets)&&Directory.GetFiles(tickets,"*.dat").Length>0)throw new InvalidOperationException("更新失败留下了未使用的游戏交接文件");
            checks.Add("completed registration survives update failure and retries without duplicate registration");
            checks.Add("failed update creates no unused game handoff token");
            File.WriteAllText(Path.Combine(folder,"appearance-report.json"),LauncherAccount.Json.Serialize(new {passed=true,checks=checks}),Encoding.UTF8);Close();return;
        }
        CaptureClient(Path.Combine(folder,"launcher-login.png"));
        if(stage=="register")toggle.PerformClick();
        if(stage!="resume"){username.Text=Convert.ToString(test["name"]);password.Text=Convert.ToString(test["password"]);confirmation.Text=password.Text;}
        remember.Checked=true;
        CaptureClient(Path.Combine(folder,"launcher-form.png"));
        await Start();
        if(stage=="bad-password"&&Visible&&!busy){
            File.WriteAllText(Path.Combine(folder,"expected-error.json"),LauncherAccount.Json.Serialize(new {message=note.Text,enabled=submit.Enabled}),Encoding.UTF8);Close();return;
        }
        if(!IsDisposed&&Visible){
            File.WriteAllText(Path.Combine(folder,"launcher-error.txt"),note.Text,Encoding.UTF8);Result=2;Close();
        }
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.ScaleTransform(displayScale,displayScale);g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.PixelOffsetMode=PixelOffsetMode.HighQuality;
        using(var background=new LinearGradientBrush(new Rectangle(0,0,344,DesignHeight),Color.FromArgb(25,36,54),Color.FromArgb(12,20,34),70))g.FillRectangle(background,0,0,344,DesignHeight);
        using(var accent=new SolidBrush(Color.FromArgb(237,104,48)))g.FillRectangle(accent,44,68,36,4);
        using(var small=new Font("Microsoft YaHei UI",10,FontStyle.Bold))using(var muted=new SolidBrush(Color.FromArgb(147,163,185)))g.DrawString("AVID WHEELS  /  HD",small,muted,43,91);
        using(var header=new Font("Microsoft YaHei UI",34,FontStyle.Bold))g.DrawString("燃烧战车",header,Brushes.White,36,130);
        using(var small=new Font("Microsoft YaHei UI",12))using(var muted=new SolidBrush(Color.FromArgb(180,192,209)))g.DrawString("高清重制版",small,muted,44,205);
        // A restrained ballistic arc is drawn at native resolution; no enlarged
        // low-resolution room texture or unrelated promotional illustration.
        using(var arc=new Pen(Color.FromArgb(67,85,110),1.5f)){
            arc.DashPattern=new float[]{3,5};g.DrawBezier(arc,44,439,117,297,223,299,300,439);
        }
        using(var target=new Pen(Color.FromArgb(237,104,48),2)){
            g.DrawEllipse(target,287,428,20,20);g.DrawLine(target,297,423,297,433);g.DrawLine(target,297,443,297,453);g.DrawLine(target,282,438,292,438);g.DrawLine(target,302,438,312,438);
        }
        using(var small=new Font("Microsoft YaHei UI",10))using(var muted=new SolidBrush(Color.FromArgb(147,163,185)))g.DrawString("经典战车 · 回合对战\n宽屏高清 · 好友联机",small,muted,44,514);
        using(var header=new Font("Microsoft YaHei UI",23,FontStyle.Bold))using(var ink=new SolidBrush(Color.FromArgb(30,40,57)))g.DrawString(registering?"创建账号":"欢迎回来",header,ink,394,45);
        using(var small=new Font("Microsoft YaHei UI",10))using(var muted=new SolidBrush(Color.FromArgb(111,123,141)))g.DrawString(registering?"注册后即可进入游戏":"登录燃烧战车，进入游戏",small,muted,397,91);
        using(var line=new Pen(Color.FromArgb(230,234,240)))g.DrawLine(line,400,491,856,491);
    }
}
