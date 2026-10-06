// Compiled alongside the PATCHED ORIGINAL Client.cs and NetworkTicker.cs,
// plus verbatim RealmManager lifecycle methods. Only external DB/transport,
// world/player dependencies are fixtures; lifecycle logic is never duplicated.
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using wServer.networking;
using wServer.networking.svrPackets;
using wServer.realm;

namespace log4net.Core { public class Level { public static readonly Level Verbose = new Level(); } }
namespace log4net
{
    public interface ILog
    {
        ILog Logger { get; }
        void Log(Type t, log4net.Core.Level l, string s, object o);
        void Info(string s); void InfoFormat(string s); void Warn(string s);
        void Error(object o); void Error(string s, Exception e); void Fatal(string s, Exception e);
    }
    public class LogManager : ILog
    {
        public static int Failures;
        public static ILog GetLogger(Type t) { return new LogManager(); }
        public ILog Logger { get { return this; } }
        public void Log(Type t, log4net.Core.Level l, string s, object o) {}
        public void Info(string s) {} public void InfoFormat(string s) {} public void Warn(string s) {}
        public void Error(object o) { Interlocked.Increment(ref Failures); }
        public void Error(string s, Exception e) { Interlocked.Increment(ref Failures); }
        public void Fatal(string s, Exception e) { Interlocked.Increment(ref Failures); }
    }
}
namespace db.JsonObjects
{
    public class Account { public string AccountId; public bool Banned; }
    public class Char { public int CharacterId; public int HP; public int Experience; public int[] Equipment; }
    public class GiftCode
    {
        public static GiftCode GenerateRandom(object o) { return new GiftCode(); }
        public string ToJson() { return "fixture"; }
    }
}
// Original db/Models.cs declares these two DTOs in the global namespace.
public class Account : db.JsonObjects.Account {}
public class Char : db.JsonObjects.Char {}
namespace db
{
    public class Database
    {
        public int Saves, Unlocks, LastSeen;
        public bool FailSave;
        public readonly List<string> Events = new List<string>();
        public db.JsonObjects.Char Saved;
        public void SaveCharacter(db.JsonObjects.Account a, db.JsonObjects.Char c)
        {
            if (a == null || c == null) throw new Exception("null source persistence identity");
            if (FailSave) throw new InvalidOperationException("fixture save failure");
            Saved = new db.JsonObjects.Char { CharacterId = c.CharacterId, HP = c.HP,
                Experience = c.Experience, Equipment = (int[])c.Equipment.Clone() };
            Saves++; Events.Add("save:" + a.AccountId);
        }
        public void UpdateLastSeen(string a, int c, string w) { LastSeen++; Events.Add("last:" + a + ":" + w); }
        public void UnlockAccount(db.JsonObjects.Account a)
        {
            if (a == null) throw new Exception("null source unlock identity");
            Unlocks++; Events.Add("unlock:" + a.AccountId);
        }
        public string GenerateGiftcode(string c, string a) { return "fixture"; }
    }
}
namespace wServer.realm.entities.player
{
    public class Player
    {
        public Client Client;
        public World Owner;
        public bool Disposed;
        public bool FailSnapshot;
        public int HP = 137, Experience = 928;
        public int[] Equipment = new int[] { 17, 23, 31 };
        public void SaveToCharacter()
        {
            if (Disposed || Client.Character == null) throw new Exception("snapshot after disposal");
            if (FailSnapshot) throw new Exception("fixture snapshot failure");
            Client.Character.HP = HP;
            Client.Character.Experience = Experience;
            Client.Character.Equipment = (int[])Equipment.Clone();
        }
        public void Dispose() { Disposed = true; }
        public void SendInfo(string s) {}
    }
}
namespace wServer
{
    public static class Program { public static readonly FixtureSettings Settings = new FixtureSettings(); }
    public class FixtureSettings
    {
        public string GetValue(string key) { return "fixture"; }
        public T GetValue<T>(string key) { return default(T); }
    }
}
namespace wServer.networking.cliPackets { public class ClientPacket : Packet {} }
namespace wServer.networking.svrPackets { public class ReconnectPacket : Packet {} }
namespace wServer.networking
{
    public enum PacketID { Fixture = 1 }
    public class Packet { public PacketID ID = PacketID.Fixture; }
    public class RC4 { public RC4(byte[] b) {} }
    public interface IPacketHandler { void Handle(Client c, cliPackets.ClientPacket p); }
    public class PacketHandlers { public static Dictionary<PacketID, IPacketHandler> Handlers = new Dictionary<PacketID, IPacketHandler>(); }
    public class NetworkHandler
    {
        public static int Sends;
        public NetworkHandler(Client c, Socket s) {} public void BeginHandling() {}
        public void SendPacket(Packet p) { Interlocked.Increment(ref Sends); }
        public void SendPackets(IEnumerable<Packet> p) {} public void Dispose() {}
    }
}
namespace wServer.realm
{
    public class wRandom {}
    public enum PendingPriority { Emergent, Destruction, Networking, Normal, Creation }
    public struct RealmTime {}
    public class World
    {
        public int Id = 32; public string Name = "NexusPortal.Golem";
        public int Leaves;
        public void LeaveWorld(wServer.realm.entities.player.Player p) { Leaves++; p.Owner = null; }
    }
    public class BoundedQueue<T>
    {
        private readonly Queue<T> items = new Queue<T>();
        public void Add(T item) { lock (items) { items.Enqueue(item); Monitor.PulseAll(items); } }
        public T Take()
        {
            lock (items)
            {
                var deadline = DateTime.UtcNow.AddSeconds(5);
                for (int n = 0; items.Count == 0 && n < 16; n++)
                {
                    var left = deadline - DateTime.UtcNow;
                    if (left <= TimeSpan.Zero || !Monitor.Wait(items, left)) break;
                }
                if (items.Count == 0) throw new Exception("bounded fixture queue deadline/attempt cap");
                return items.Dequeue();
            }
        }
        public int Count { get { lock (items) return items.Count; } }
    }
    public class LogicTicker
    {
        private readonly BoundedQueue<Action<RealmTime>> actions = new BoundedQueue<Action<RealmTime>>();
        public void AddPendingAction(Action<RealmTime> a, PendingPriority p) { actions.Add(a); }
        public void DrainOne() { actions.Take()(new RealmTime()); }
        public int Count { get { return actions.Count; } }
    }
    public class DatabaseTicker
    {
        private class Work { public Action<db.Database> Callback; public TaskCompletionSource<int> Completion; }
        private readonly BoundedQueue<Work> work = new BoundedQueue<Work>();
        public readonly db.Database Store = new db.Database();
        public Task DoActionAsync(Action<db.Database> callback)
        {
            var w = new Work { Callback = callback, Completion = new TaskCompletionSource<int>() };
            work.Add(w); return w.Completion.Task;
        }
        public void RunOne()
        {
            var w = work.Take();
            // Match ORIGINAL DatabaseTicker's swallow/log callback behavior.
            try { w.Callback(Store); } catch (Exception e) { log4net.LogManager.GetLogger(GetType()).Error(e); }
            w.Completion.SetResult(0);
        }
        public void FailAcquisition() { work.Take().Completion.SetException(new Exception("fixture DB acquisition failed")); }
        public int Count { get { return work.Count; } }
    }
    public partial class RealmManager
    {
        public readonly ConcurrentDictionary<string, Client> Clients = new ConcurrentDictionary<string, Client>();
        public readonly LogicTicker Logic = new LogicTicker();
        public readonly DatabaseTicker Database = new DatabaseTicker();
        public class FixtureGameData : IDisposable { public int Disposals; public void Dispose() { Disposals++; } }
        public FixtureGameData GameData = new FixtureGameData();
        public bool Terminating;
        public int MaxClients = 100;
        private bool stopping;
        private int nextClientId;
        private static readonly log4net.ILog log = log4net.LogManager.GetLogger(typeof(RealmManager));
        private Thread logic, network;
        public void InitializeStoppedTickerFixtures()
        {
            logic = new Thread(() => {}); network = new Thread(() => {});
            logic.Start(); network.Start();
            if (!logic.Join(5000) || !network.Join(5000)) throw new Exception("fixture thread deadline");
        }
    }
}
class LifecycleRegression
{
    static int cases;
    static void Check(bool b, string s) { if (!b) throw new Exception(s); }
    static Client New(RealmManager m, string id = "42", bool registered = true)
    {
        var c = new Client(m, new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp));
        c.Account = new Account { AccountId = id };
        c.Character = new Char { CharacterId = 2 };
        c.Stage = ProtocalStage.Ready;
        c.Player = new wServer.realm.entities.player.Player { Client = c, Owner = new World() };
        if (registered) Check(m.TryConnect(c), "original TryConnect registers fixture");
        return c;
    }
    static void Finish(RealmManager m, Task done)
    {
        m.Logic.DrainOne();
        Check(done.Wait(5000), "bounded terminal completion");
    }
    static void Persisted(RealmManager m)
    {
        var s = m.Database.Store;
        Check(s.Saved.CharacterId == 2 && s.Saved.HP == 137 && s.Saved.Experience == 928 && s.Saved.Equipment[2] == 31,
            "original character identity/HP/experience/equipment preserved");
        Check(s.LastSeen == 1 && s.Events[s.Events.Count - 1] == "unlock:42", "last-seen/save precede unlock");
    }
    static void LogoutRace()
    {
        var m = new RealmManager(); var c = New(m); var player = c.Player; var world = player.Owner;
        c.Disconnect(); c.Disconnect(); c.Dispose();
        Check(m.Logic.Count == 1, "duplicate logout/dispose queues exactly one terminal request");
        m.Logic.DrainOne();
        var done = m.Disconnect(c);
        Check(Object.ReferenceEquals(done, m.Disconnect(c)), "idempotent stable disconnect Task");
        Check(!done.IsCompleted && m.Database.Count == 1, "force genuine outstanding Save await");
        Check(c.Account != null && c.Character != null && !player.Disposed, "public Dispose defers field release");
        // Also force the old crash's exact mutable-account condition while the
        // awaited save is outstanding: captured DB identity must survive it.
        c.Account = null;
        var newer = New(m, registered: false); m.Clients["42"] = newer;
        m.Database.RunOne(); Finish(m, done);
        Client current;
        Check(m.Clients.TryGetValue("42", out current) && Object.ReferenceEquals(current, newer),
            "old completion cannot remove newer same-account client");
        Check(c.Account == null && c.Character == null && player.Disposed && world.Leaves == 1, "single ordered disposal/detach");
        Check(m.Database.Store.Saves == 1 && m.Database.Store.Unlocks == 1, "one terminal save/unlock");
        Persisted(m); c.Dispose(); Check(m.Logic.Count == 0, "post-completion duplicate disposal inert");
        Cleanup(m, newer); cases++;
    }
    static void ReconnectBarrier()
    {
        var m = new RealmManager(); var old = New(m);
        old.Reconnect(new ReconnectPacket()); old.Reconnect(new ReconnectPacket()); m.Logic.DrainOne();
        int before = NetworkHandler.Sends;
        var newer = New(m, registered: false);
        Check(!m.TryConnect(newer), "cannot replace old socket before persistence barrier");
        Check(NetworkHandler.Sends == before && m.Database.Store.Unlocks == 0, "no early reconnect/unlock");
        m.Database.RunOne(); m.Logic.DrainOne();
        Check(NetworkHandler.Sends == before + 1, "one reconnect only after persistence");
        Check(m.TryConnect(newer), "completed reconnect permits real TryConnect handoff");
        m.Logic.DrainOne(); // old Disconnect scheduled by TryConnect
        var done = m.Disconnect(old); Finish(m, done);
        Check(Object.ReferenceEquals(m.Clients["42"], newer), "handoff survives old cleanup");
        Check(m.Database.Count == 0 && m.Database.Store.Saves == 1 && m.Database.Store.Unlocks == 1,
            "old logout reuses barrier: no late save/unlock against new login");
        Persisted(m); Cleanup(m, newer); cases++;
    }
    static void SerializedSaves()
    {
        var m = new RealmManager(); var c = New(m);
        var first = c.Save(); var second = c.Save();
        Check(m.Database.Count == 1, "ordinary saves serialized");
        var done = m.Disconnect(c); c.Dispose();
        m.Database.RunOne(); Check(first.Wait(5000), "first save bounded");
        m.Database.RunOne(); Check(second.Wait(5000), "second save bounded");
        Check(m.Database.Store.Unlocks == 0 && !done.IsCompleted, "ordinary save cannot unlock or dispose");
        m.Database.RunOne(); Finish(m, done);
        Check(m.Database.Store.Saves == 3 && m.Database.Store.Unlocks == 1 && m.Clients.Count == 0,
            "terminal drains earlier saves then saves/unlocks once"); cases++;
    }
    static void DisconnectedPacket()
    {
        var m = new RealmManager(); var c = New(m); var ticker = new NetworkTicker(m);
        var processed = new ManualResetEventSlim();
        PacketHandlers.Handlers[PacketID.Fixture] = new SignalHandler(processed);
        c.Disconnect();
        var sentinel = New(m, "sentinel");
        ticker.AddPendingPacket(c, new wServer.networking.cliPackets.ClientPacket());
        ticker.AddPendingPacket(sentinel, new wServer.networking.cliPackets.ClientPacket());
        var thread = new Thread(ticker.TickLoop); thread.Start();
        try
        {
            Check(processed.Wait(5000), "network fixture bounded queue drain");
            Check(Object.ReferenceEquals(m.Clients["42"], c), "NetworkTicker cannot key-remove saving client");
        }
        finally { m.Terminating = true; Check(thread.Join(5000), "owned network thread stopped"); processed.Dispose(); }
        m.Logic.DrainOne(); var done = m.Disconnect(c); m.Database.RunOne(); Finish(m, done);
        Cleanup(m, sentinel); cases++;
    }
    class SignalHandler : IPacketHandler
    {
        readonly ManualResetEventSlim signal;
        public SignalHandler(ManualResetEventSlim s) { signal = s; }
        public void Handle(Client c, wServer.networking.cliPackets.ClientPacket p) { signal.Set(); }
    }
    static void SaveFailure(bool acquisition, bool snapshot)
    {
        var m = new RealmManager(); var c = New(m);
        m.Database.Store.FailSave = !acquisition; c.Player.FailSnapshot = snapshot;
        int errors = log4net.LogManager.Failures;
        c.Reconnect(new ReconnectPacket()); int sends = NetworkHandler.Sends; m.Logic.DrainOne();
        if (!snapshot) { if (acquisition) m.Database.FailAcquisition(); else m.Database.RunOne(); }
        m.Logic.DrainOne(); // failure queues Disconnect, never async-void death
        var done = m.Disconnect(c); Finish(m, done);
        Check(m.Database.Store.Unlocks == 0 && NetworkHandler.Sends == sends, "failed barrier neither unlocks nor reconnects");
        Check(!c.CanReplaceAfterReconnect && m.Clients.Count == 0 && c.Account == null, "failed barrier cleans up without handoff");
        Check(log4net.LogManager.Failures > errors, "failure observable, not suppressed"); cases++;
    }
    static void ArenaAndUnauthenticated()
    {
        var m = new RealmManager(); var c = New(m); c.Player.Owner.Id = -6;
        var done = m.Disconnect(c); m.Database.RunOne(); Finish(m, done);
        Check(m.Database.Store.Saves == 0 && m.Database.Store.Unlocks == 1, "source arena exclusion retained; departure still unlocks");
        var guest = new Client(m, new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp));
        guest.Disconnect(); guest.Dispose(); m.Logic.DrainOne(); var guestDone = m.Disconnect(guest); Finish(m, guestDone);
        Check(m.Database.Count == 0 && guest.Socket == null, "unauthenticated teardown requires no DB identity"); cases++;
    }
    static void AuthenticationDisposeRace()
    {
        var m = new RealmManager();
        var c = new Client(m, new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp));
        bool registration = true;
        var auth = c.RunSessionAction(db =>
        {
            Check(c.Manager == m && c.Socket != null, "in-flight original auth retains client context");
            c.Account = new Account { AccountId = "42" };
            registration = m.TryConnect(c);
        });
        c.Dispose(); m.Logic.DrainOne(); var done = m.Disconnect(c);
        Check(!done.IsCompleted && !auth.IsCompleted && m.Database.Count == 1, "terminal waits for outstanding authentication");
        m.Database.RunOne(); Check(auth.Wait(5000), "bounded auth completion"); Finish(m, done);
        Check(!registration && c.Account == null && c.Manager == null && m.Clients.Count == 0,
            "disconnected pending auth cannot resurrect/register disposed client");
        Check(m.Database.Store.Unlocks == 0 && m.Database.Store.Saves == 0, "unowned auth must not unlock another account");
        cases++;
    }
    static void RejectedSessionCannotUnlock()
    {
        var m = new RealmManager(); var owner = New(m); var rejected = New(m, registered: false);
        Check(!m.TryConnect(rejected), "second same-account login rejected before transfer barrier");
        rejected.Disconnect(); rejected.Dispose(); m.Logic.DrainOne();
        var done = m.Disconnect(rejected); Finish(m, done);
        Check(m.Database.Count == 0 && m.Database.Store.Unlocks == 0 && m.Database.Store.Saves == 0,
            "verified but unregistered client cannot save/unlock another session's account");
        Check(Object.ReferenceEquals(m.Clients["42"], owner), "rejected logout cannot remove account owner");
        Cleanup(m, owner); cases++;
    }
    static void ShutdownDrain()
    {
        var m = new RealmManager(); var c = New(m); m.InitializeStoppedTickerFixtures();
        var server = new Server(m); server.Stop();
        Check(m.Database.Count == 0 && m.Logic.Count == 1, "Server.Stop synchronous: no async-void save tail");
        Exception failure = null;
        var thread = new Thread(() => { try { m.Stop(); } catch (Exception ex) { failure = ex; } });
        thread.Start();
        try
        {
            m.Logic.DrainOne(); // queued socket disconnect
            m.Logic.DrainOne(); // manager shutdown's terminal task request
            var newcomer = New(m, registered: false);
            Check(!m.TryConnect(newcomer), "shutdown refuses new admissions");
            Check(!m.Terminating && m.Database.Store.Unlocks == 0 && c.Account != null,
                "shutdown leaves logic alive and identity retained during pending save");
            m.Database.RunOne(); m.Logic.DrainOne();
            Check(thread.Join(5000) && failure == null, "bounded real manager shutdown drain");
            Check(m.Terminating && m.Clients.Count == 0 && m.GameData.Disposals == 1 && c.Account == null,
                "shutdown completes ordered save/unlock/dispose before ticker/resource termination");
            Check(m.Database.Store.Unlocks == 1 && m.Database.Store.Saves == 1, "shutdown shares one departure barrier");
            m.Stop(); Check(m.GameData.Disposals == 1, "duplicate manager stop inert");
            Cleanup(m, newcomer); cases++;
        }
        finally { Check(thread.Join(20000), "owned shutdown thread stopped"); }
    }
    static void Cleanup(RealmManager m, Client c)
    {
        var done = m.Disconnect(c);
        if (m.Database.Count > 0) m.Database.RunOne();
        Finish(m, done);
    }
    public static void Main()
    {
        LogoutRace(); ReconnectBarrier(); SerializedSaves(); DisconnectedPacket();
        SaveFailure(false, false); SaveFailure(true, false); SaveFailure(false, true);
        ArenaAndUnauthenticated(); RejectedSessionCannotUnlock(); AuthenticationDisposeRace(); ShutdownDrain();
        Console.WriteLine("compiled-original-lifecycle: PASS (" + cases + " forced interleavings)");
    }
}
