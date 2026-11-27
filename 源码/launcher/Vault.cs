using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

// The native game exchanges UTF-8 records over stdin/stdout. Preserve both
// legacy DPAPI filenames and entropy so existing opt-in logins survive updates.
internal static class Vault
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("BurningChariotHD.Session.v1");
    private static int Main(string[] args)
    {
        try
        {
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BurningChariotHD");
            string isolated = Environment.GetEnvironmentVariable("BCHD_VAULT_ROOT");
            if (!String.IsNullOrEmpty(isolated)) root = Path.GetFullPath(isolated);
            if (args.Length != 1) return 2;
            Console.InputEncoding = new UTF8Encoding(false);
            Console.OutputEncoding = new UTF8Encoding(false);
            string input = Console.ReadLine() ?? "";
            string operation = args[0];
            bool account = operation.EndsWith("-account",StringComparison.Ordinal);
            if (account) operation = operation.Substring(0,operation.Length-8);
            string path = Path.Combine(root, account ? "account.dat" : "session.dat");
            if (operation == "write")
            {
                Directory.CreateDirectory(root);
                byte[] plain = Encoding.UTF8.GetBytes(input);
                try
                {
                    byte[] encrypted = ProtectedData.Protect(plain, Entropy, DataProtectionScope.CurrentUser);
                    string pending = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
                    File.WriteAllBytes(pending, encrypted);
                    if (File.Exists(path)) File.Replace(pending, path, null); else File.Move(pending, path);
                }
                finally { Array.Clear(plain, 0, plain.Length); }
                Console.WriteLine("ok");
            }
            else if (operation == "read")
            {
                if (!File.Exists(path)) { Console.WriteLine(""); return 0; }
                byte[] plain = ProtectedData.Unprotect(File.ReadAllBytes(path), Entropy, DataProtectionScope.CurrentUser);
                try { Console.WriteLine(Encoding.UTF8.GetString(plain)); }
                finally { Array.Clear(plain, 0, plain.Length); }
            }
            else if (operation == "clear") { if (File.Exists(path)) File.Delete(path); Console.WriteLine(""); }
            else if(args[0]=="consume-handoff")
            {
                Guid id;if(!Guid.TryParseExact(input,"N",out id))return 2;
                string handoff=Path.Combine(root,"handoff",id.ToString("N")+".dat");
                if(!File.Exists(handoff)||File.GetLastWriteTimeUtc(handoff)<DateTime.UtcNow.AddMinutes(-15))return 2;
                byte[] encrypted=File.ReadAllBytes(handoff);File.Delete(handoff);
                byte[] plain=ProtectedData.Unprotect(encrypted,Entropy,DataProtectionScope.CurrentUser);
                try{Console.WriteLine(Encoding.UTF8.GetString(plain));}finally{Array.Clear(plain,0,plain.Length);}
            }
            else return 2;
            return 0;
        }
        catch { Console.WriteLine(""); return 1; }
    }
}
