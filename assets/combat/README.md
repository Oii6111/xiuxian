# A 专属短音效

strike/spell/chime.wav 为本任务用正弦谐波、指数衰减和 PCM 合成生成的原创短音，未使用外部录音。普攻与术法已接入关卡；chime 供庆典使用。像素图复用 assets/pixel 和 assets/pixel_campaign，来源约定见各目录 PROMPTS.md。

Boss cues (boss_*.wav) are original deterministic synthesis from tools/generate_boss_audio.py: tell, rush, shot, impact, hit, phase. No third-party game audio.

Challenge cues add perfect / stagger. boss_motion.gdshader adds local motion and tell rims using the explicit combat clock; hero_silhouette.gdshader preserves visibility behind large bosses. All shader code and synthesized cues are original.
