import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

import "./App.css";

function App() {

  const [adbPaths, setAdbPaths] = useState<string[]>([]);
  const [selectedAdbPath, setSelectedAdbPath] = useState("");
  const [deeplink, setDeeplink] = useState("");
  const [packageTarget, setPackageTarget] = useState("");
  const [logs, setLogs] = useState("");

  // Load ADB paths from Rust on startup
  useEffect(() => {
    invoke("init");
    async function loadADBPaths() {
      try {
        const paths = await invoke<string[]>("fetch_adb_paths");
        setAdbPaths(paths);
        if (paths.length > 0) setSelectedAdbPath(paths[0]);
        console.error(adbPaths);
      } catch (err) {
        console.error("Failed to fetch ADB paths:", err);
      }
    }

    loadADBPaths();
  }, []);

  const sendMessage = async () => {
    try {
      const response = await invoke<string>("send_deeplink", {
        adbPath: selectedAdbPath,
        packageName: packageTarget,
        deeplink: deeplink,
      });
      console.log("Response from Rust:", response);
      setLogs(() => response);
    } catch (error) {
      console.error("Error invoking command:", error);
      setLogs(() => "\nError: " + String(error));
    }
  };

  return (
    <div className="flex flex-col h-screen bg-slate-700 text-white h-full p-4">
      <h2 className="text-xl font-bold mb-80 text-center bg-[#1B3C53]">SimDeeplink</h2>
      <div className="p-4 bg-slate-600 rounded-xl">
        Deeplink
        <div className="flex flex-col box" style={{ paddingBottom: 12 }}>
          <div className="flex">
            <input
              type="text"
              value={deeplink}
              onChange={(e) => setDeeplink(e.target.value)}
              placeholder="Enter Deeplink URL"
              className="flex-grow p-2 rounded text-black"
            />
            <span>&nbsp;&nbsp;</span>
            <button className="bg-gray-800 hover:bg-gray-700 text-white px-4 py-2 mx-20 rounded">
              <img src="/eraser.png" width="16px" />
            </button>
          </div>
          <div className="flex" style={{ paddingTop: 12}}>
            <span>
              ADB Executeable
            </span>
            <span>&nbsp;&nbsp;</span>
            <select
              value={selectedAdbPath}
              onChange={(e) => setSelectedAdbPath(e.target.value)}
              className="flex-grow p-2 rounded text-black"
            >
              {adbPaths.length === 0 ? (
                <option>Loading...</option>
              ) : (
                adbPaths.map((path, idx) => (
                  <option key={idx} value={path}>
                    {path}
                  </option>
                ))
              )}
            </select>
          </div>
          <div className="flex" style={{ paddingTop: 12}}>
            <span>Package Target (Optional)</span>
            <span>&nbsp;&nbsp;</span>
            <input
              type="text"
              value={packageTarget}
              onChange={(e) => setPackageTarget(e.target.value)}
              placeholder="Package"
              className="flex-grow p-2 rounded text-black"
            />
            <span>&nbsp;&nbsp;</span>
            <button className="bg-gray-800 hover:bg-gray-700 text-white px-4 py-2 mx-20 rounded">
              <img src="/eraser.png" width="16px" />
            </button>
          </div>
          <div className="flex" style={{ paddingTop: 12}}>
            <span>
              Emulator Target
            </span>
            <span>&nbsp;&nbsp;</span>
            <select className="flex-grow p-2 rounded text-black">
              <option>Pilih</option>
            </select>
            <span>&nbsp;&nbsp;</span>
            <button className="bg-gray-800 hover:bg-gray-700 text-white px-4 py-2 mx-20 rounded">
              <img src="/eraser.png" width="16px" />
            </button>
          </div>
          <div className="flex" style={{ paddingTop: 12}}>
            <span>
              Delay
            </span>
            <span>&nbsp;&nbsp;</span>
            <input
              type="number"
              placeholder="in Seconds"
              className="flex-grow p-2 rounded text-black"
            />
            <span className="flex-grow">&nbsp;&nbsp;</span>
            <button
            className="flex-none bg-gray-800 hover:bg-gray-700 text-white px-4 py-2 mx-20 rounded"
            onClick={sendMessage}
            >
              Execute Deeplink
            </button>
          </div>
        </div>
      </div>
      <span style={{ paddingTop: 12 }}></span>
      <textarea
        value={logs}
        readOnly
        placeholder="Logs or text area..."
        className="flex-grow p-2 resize-none" // need to show output of send_deeplink in here
      />
    </div>
  );
}


export default App;