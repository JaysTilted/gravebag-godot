// GRAVEBAG protocol oracle: execute the ORIGINAL backend packet writers.
// Source: ossimc82/fabiano-swagger-of-doom 6fd20aad4a7905b13f25389c68368a942a2b68cb
// AGPL-3.0; added 2026-10-06. No server/database/network is started.
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using wServer;
using wServer.networking;
using wServer.networking.svrPackets;
using wServer.realm;

class Oracle
{
    static void Emit(string name, Packet packet)
    {
        using (var stream = new MemoryStream())
        using (var writer = new NWriter(stream))
        {
            // Skip encryption and framing: compare plaintext payload with Godot codec.
            var method = packet.GetType().GetMethod("Write", BindingFlags.NonPublic | BindingFlags.Instance,
                null, new[] { typeof(Client), typeof(NWriter) }, null);
            method.Invoke(packet, new object[] { null, writer });
            writer.Flush();
            Console.WriteLine(name + "\t" + (byte)packet.ID + "\t" + BitConverter.ToString(stream.ToArray()).Replace("-", "").ToLowerInvariant());
        }
    }

    static ObjectStats Status()
    {
        return new ObjectStats {
            Id = 1234, Position = new Position(12.5f, -3.25f),
            Stats = new[] {
                new KeyValuePair<StatsType, object>(StatsType.HP, 87),
                new KeyValuePair<StatsType, object>(StatsType.Name, "Gravebag"),
                new KeyValuePair<StatsType, object>(StatsType.AccountId, "42"),
                new KeyValuePair<StatsType, object>(StatsType.OwnerAccountId, "43"),
                new KeyValuePair<StatsType, object>(StatsType.Guild, "Nexus"),
                new KeyValuePair<StatsType, object>(StatsType.PetSkin, "skin"),
                new KeyValuePair<StatsType, object>(StatsType.MaximumHP, 100)
            }
        };
    }

    static int Main()
    {
        try {
            Emit("map_info_xml32", new MapInfoPacket {
                Width = 100, Height = 80, Name = "Nexus", ClientWorldName = "GRAVEBAG",
                Seed = 12345, Background = 0, Difficulty = 1, AllowTeleport = true, ShowDisplays = false,
                ClientXML = new[] { "<Objects/>" }, ExtraXML = new[] { "<Grounds/>" }
            });
            Emit("new_tick_utf_stats", new NewTickPacket {
                TickId = 7, TickTime = 200, UpdateStatuses = new[] { Status() }
            });
            Emit("update_objects", new UpdatePacket {
                Tiles = new[] { new UpdatePacket.TileData { X = 12, Y = 9, Tile = 0x0123 } },
                NewObjects = new[] { new ObjectDef { ObjectType = 0x030e, Stats = Status() } },
                RemovedObjectIds = new[] { 44, 45 }
            });
            return 0;
        } catch (Exception e) {
            Console.Error.WriteLine(e.GetType().Name + ": " + e.Message);
            return 1;
        }
    }
}
