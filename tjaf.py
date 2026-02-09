import os
import re
from typing import Dict, List, Optional

class Tja:
    def __init__(self, text: str):
        self.text = text
        self.title: Optional[str] = None
        self.subtitle: Optional[str] = None
        self.title_ja: Optional[str] = None
        self.subtitle_ja: Optional[str] = None
        self.wave: Optional[str] = None
        self.offset: Optional[float] = None
        self.courses: Dict[str, Dict[str, Optional[int]]] = {}
        # Dan-specific fields
        self.is_dan: bool = False
        self.dan_exams: List[Dict] = []  # [{"type": "g", "red": 97, "gold": 100, "scope": "m"}, ...]
        self.dan_songs: List[Dict] = []  # [{"title": "RPG", "wave": "RPG.ogg", "delay": 0}, ...]
        self._parse()

    def _parse_exam(self, val: str) -> Optional[Dict]:
        """Parse EXAM line: g,97,100,m -> {"type": "g", "red": 97, "gold": 100, "scope": "m"}"""
        parts = val.split(",")
        if len(parts) >= 4:
            try:
                return {
                    "type": parts[0].strip().lower(),
                    "red": float(parts[1].strip()),
                    "gold": float(parts[2].strip()),
                    "scope": parts[3].strip().lower()
                }
            except (ValueError, IndexError):
                return None
        return None

    def _parse_nextsong(self, val: str, lines: List[str], line_idx: int) -> Optional[Dict]:
        """Parse #NEXTSONG line: title,subtitle,genre,audio_file,scoreInit,scoreDiff"""
        parts = val.split(",")
        if len(parts) >= 4:
            song_info = {
                "title": parts[0].strip(),
                "subtitle": parts[1].strip() if len(parts) > 1 else "",
                "genre": parts[2].strip() if len(parts) > 2 else "",
                "wave": parts[3].strip() if len(parts) > 3 else "",
                "scoreinit": float(parts[4].strip()) if len(parts) > 4 and parts[4].strip() else 0,
                "scorediff": float(parts[5].strip()) if len(parts) > 5 and parts[5].strip() else 0,
                "delay": 0,
                "exam": None  # Per-song exam (EXAM4 after #NEXTSONG)
            }
            # Look for EXAM4 and #DELAY after #NEXTSONG
            for i in range(line_idx + 1, min(line_idx + 10, len(lines))):
                next_line = lines[i].strip()
                if next_line.startswith("#DELAY"):
                    try:
                        song_info["delay"] = float(next_line.split()[1])
                    except (ValueError, IndexError):
                        pass
                elif next_line.upper().startswith("EXAM4:"):
                    exam_val = next_line.split(":", 1)[1]
                    song_info["exam"] = self._parse_exam(exam_val)
                elif next_line.startswith("#") and "NEXTSONG" in next_line.upper():
                    break  # Stop at next song
                elif any(c.isdigit() for c in next_line) and "," in next_line:
                    break  # Stop at note data
            return song_info
        return None

    def _parse(self) -> None:
        lines = self.text.split("\n")
        current_course: Optional[str] = None
        in_dan_course = False
        
        for line_idx, raw in enumerate(lines):
            line = raw.strip()
            if not line:
                continue
            
            # Handle comments (but preserve MAKER lines)
            if "//" in line and not line.lower().startswith("maker:"):
                line = line.split("//")[0].strip()
                if not line:
                    continue
            
            # Check for #NEXTSONG command (Dan-specific)
            if line.upper().startswith("#NEXTSONG"):
                val = line.split(" ", 1)[1] if " " in line else ""
                song_info = self._parse_nextsong(val, lines, line_idx)
                if song_info:
                    self.dan_songs.append(song_info)
                continue
            
            if ":" in line:
                k, v = line.split(":", 1)
                key = k.strip().upper()
                val = v.strip()
                
                if key == "TITLE":
                    self.title = val or None
                elif key == "TITLEJA":
                    self.title_ja = val or None
                elif key == "SUBTITLE":
                    self.subtitle = val or None
                elif key == "SUBTITLEJA":
                    self.subtitle_ja = val or None
                elif key == "WAVE":
                    self.wave = val or None
                elif key == "OFFSET":
                    try:
                        self.offset = float(val)
                    except ValueError:
                        self.offset = None
                elif key == "COURSE":
                    course_val = val.strip().upper()
                    course_map = {
                        "EASY": "easy",
                        "NORMAL": "normal",
                        "HARD": "hard",
                        "ONI": "oni",
                        "EDIT": "ura",
                        "URA": "ura",
                        "DAN": "dan",
                        "TOWER": "tower",
                    }
                    current_course = course_map.get(course_val)
                    if current_course in ("dan", "tower"):
                        self.is_dan = True
                        in_dan_course = True
                    else:
                        in_dan_course = False
                    if current_course and current_course not in self.courses:
                        self.courses[current_course] = {"stars": None, "branch": False}
                elif key == "LEVEL" and current_course:
                    try:
                        stars = int(re.split(r"\s+", val)[0])
                    except ValueError:
                        stars = None
                    self.courses[current_course]["stars"] = stars
                # Parse EXAM1-4 for Dan courses
                elif key in ("EXAM1", "EXAM2", "EXAM3", "EXAM4") and in_dan_course:
                    exam = self._parse_exam(val)
                    if exam:
                        exam["id"] = int(key[-1])  # 1, 2, 3, or 4
                        # For EXAM1-3, add to global dan_exams
                        if key != "EXAM4":
                            self.dan_exams.append(exam)
            else:
                if current_course and (line.startswith("BRANCHSTART") or line.startswith("#BRANCHSTART")):
                    self.courses[current_course]["branch"] = True

    def get_all_audio_files(self) -> List[str]:
        """Get list of all audio files needed for this TJA (for Dan mode)"""
        audio_files = []
        if self.wave:
            audio_files.append(os.path.basename(self.wave))
        for song in self.dan_songs:
            if song.get("wave"):
                wave_file = os.path.basename(song["wave"])
                if wave_file not in audio_files:
                    audio_files.append(wave_file)
        return audio_files

    def to_mongo(self, song_id: str, created_ns: int) -> Dict:
        ext = None
        if self.wave:
            base = os.path.basename(self.wave)
            _, e = os.path.splitext(base)
            if e:
                ext = e.lstrip(".").lower()
        if not ext:
            ext = "mp3"
        courses_out: Dict[str, Optional[Dict[str, Optional[int]]]] = {}
        for name in ["easy", "normal", "hard", "oni", "ura"]:
            courses_out[name] = self.courses.get(name) or None
        
        result = {
            "id": song_id,
            "type": "tja",
            "title": self.title,
            "subtitle": self.subtitle,
            "title_lang": {
                "ja": self.title_ja or self.title,
                "en": None,
                "cn": self.title_ja or None,
                "tw": None,
                "ko": None,
            },
            "subtitle_lang": {
                "ja": self.subtitle_ja or self.subtitle,
                "en": None,
                "cn": self.subtitle_ja or None,
                "tw": None,
                "ko": None,
            },
            "courses": courses_out,
            "enabled": False,
            "category_id": None,
            "music_type": ext,
            # DB 的 offset 是"额外偏移"，TJA 自身的 OFFSET 会在前端解析时应用
            # 为避免双重偏移，这里固定为 0
            "offset": 0,
            "skin_id": None,
            "preview": 0,
            "volume": 1.0,
            "maker_id": None,
            "hash": None,
            "order": song_id,
            "created_ns": created_ns,
        }
        
        # Add Dan-specific fields if this is a Dan exam
        if self.is_dan:
            result["is_dan"] = True
            result["dan_exams"] = self.dan_exams
            result["dan_songs"] = self.dan_songs
            # For Dan, set course to "dan" type
            if "dan" in self.courses:
                result["courses"]["dan"] = self.courses["dan"]
        
        return result