# PrismaCubed Cellular JIT

This optional setup uses iOS 27 or later and a configured LocalDevVPN. PrismaCubed runs the shortcut when a game launch needs JIT and LocalDevVPN is unreachable. The launcher still performs its normal JIT request using Auto, Built-in JIT, or StikDebug.

## Create the shortcut

In Apple Shortcuts, create a shortcut named exactly **PrismaCubed JIT**. Start with a **Text** action containing the **Shortcut Input** variable. Use that text for the conditions below.

1. If the input contains `start`:
   - Run **Get Current VPN** and save that VPN object as **previous VPN** with **Store Content** if another VPN is active.
   - If the current VPN is LocalDevVPN, set an output variable to `local`. If another VPN is active, set it to `other`. If there is no current VPN, set it to `none`.
   - Unless LocalDevVPN is already connected, run LocalDevVPN’s **Connect** action. Connect it before disabling cellular so the tunnel can start while a network is available.
   - If the input contains `cellular`, run **Set Cellular Data → Off**.
   - Use **Stop and Output** with the output variable as plain text.
2. Otherwise, if the input contains `done`:
   - If it contains `cellular`, run **Set Cellular Data → On**.
   - If it contains `vpn-off`, disconnect LocalDevVPN.
   - If it contains `vpn-restore`, get the **previous VPN** object with **Get Stored Content** and pass it to **Set VPN → Connect**.

Enable **PrismaCubed Cellular JIT** in first-run setup or **Settings → Debugging**, then launch a game using Auto, Built-in JIT, or StikDebug. Running the shortcut by tapping its tile sends no command. If you interrupt a run and cellular stays off, you can turn it back on in Settings. PrismaCubed also tries to restore the pending network state on its next launch.

If the JVM needs a live debugger on a TXM device, PrismaCubed keeps the connection in place through gameplay and restores the network when the game exits. If iOS ends the process before cleanup, PrismaCubed tries again on the next launch.

To share this shortcut with testers, open it on an iPhone and use **Share → Copy iCloud Link**. Apple Shortcuts handles the import confirmation.

The command and callback design was informed by [Madeira’s JIT flow](https://github.com/kl4ng3r/Madeira/blob/main/docs/JIT.md#localdevvpn-cellular-data-and-the-madeira-jit-shortcut).
