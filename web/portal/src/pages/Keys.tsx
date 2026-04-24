import { useEffect, useState } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { format } from 'date-fns'
import { api, PassKeyRow, NewKeyResult } from '../lib/api'

export default function Keys() {
  const [keys, setKeys]           = useState<PassKeyRow[]>([])
  const [label, setLabel]         = useState('')
  const [newKey, setNewKey]       = useState<NewKeyResult | null>(null)
  const [loading, setLoading]     = useState(false)

  useEffect(() => { load() }, [])

  async function load() {
    setKeys(await api.listKeys())
  }

  async function create(e: React.FormEvent) {
    e.preventDefault()
    if (!label.trim()) return
    setLoading(true)
    try {
      const result = await api.createKey(label.trim())
      setNewKey(result)
      setLabel('')
      await load()
    } finally {
      setLoading(false)
    }
  }

  async function revoke(id: number) {
    if (!confirm('Revoke this key? The device will no longer be able to unlock.')) return
    await api.revokeKey(id)
    await load()
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Passkeys</h1>

      {/* Create form */}
      <form onSubmit={create} className="bg-white rounded-xl shadow p-5 flex gap-3">
        <input
          className="flex-1 border rounded px-3 py-2 text-sm"
          placeholder="Label (e.g. John's iPhone)"
          value={label}
          onChange={e => setLabel(e.target.value)}
        />
        <button
          type="submit"
          disabled={loading}
          className="bg-blue-600 text-white rounded px-4 py-2 text-sm font-medium hover:bg-blue-700 disabled:opacity-50"
        >
          Issue Key
        </button>
      </form>

      {/* New key QR modal */}
      {newKey && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl shadow-xl p-8 max-w-sm w-full space-y-4 text-center">
            <h2 className="text-lg font-bold">Scan to enroll: {newKey.label}</h2>
            <p className="text-sm text-gray-500">This QR code is shown once. Scan with the CopCar Passkey iOS app.</p>
            <div className="flex justify-center">
              <QRCodeSVG value={`CopCarpasskey://enroll?secret=${newKey.secret}&label=${encodeURIComponent(newKey.label)}`} size={220} />
            </div>
            <p className="text-xs text-gray-400 font-mono break-all">{newKey.secret}</p>
            <button
              onClick={() => setNewKey(null)}
              className="w-full bg-gray-900 text-white rounded px-4 py-2 text-sm font-medium hover:bg-gray-800"
            >
              Done — I've scanned the QR
            </button>
          </div>
        </div>
      )}

      {/* Keys table */}
      <div className="bg-white rounded-xl shadow overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-500 text-xs uppercase">
            <tr>
              <th className="px-4 py-3 text-left">Label</th>
              <th className="px-4 py-3 text-left">Hint</th>
              <th className="px-4 py-3 text-left">Issued</th>
              <th className="px-4 py-3 text-left">Status</th>
              <th className="px-4 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y">
            {keys.map(k => (
              <tr key={k.id} className={k.isActive ? '' : 'opacity-50'}>
                <td className="px-4 py-3 font-medium text-gray-900">{k.label}</td>
                <td className="px-4 py-3 font-mono text-gray-400">…{k.secretHint}</td>
                <td className="px-4 py-3 text-gray-500">{format(new Date(k.createdAt), 'MMM d, yyyy')}</td>
                <td className="px-4 py-3">
                  {k.isActive
                    ? <span className="text-green-600 font-medium">Active</span>
                    : <span className="text-gray-400">Revoked</span>}
                </td>
                <td className="px-4 py-3 text-right">
                  {k.isActive && (
                    <button
                      onClick={() => revoke(k.id)}
                      className="text-red-600 hover:underline text-xs"
                    >Revoke</button>
                  )}
                </td>
              </tr>
            ))}
            {keys.length === 0 && (
              <tr><td colSpan={5} className="px-4 py-8 text-center text-gray-400">No keys yet</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
