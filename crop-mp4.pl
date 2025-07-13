#!/usr/bin/perl -w                                                                                                                    

use strict;
use File::Basename;
use File::Spec;
use File::Path qw(make_path remove_tree);
use GD;
use Data::Dumper;
#use Image::Magick;                                                                                                                   
use File::Temp qw/tempfile tempdir/;
use threads;

our $fps = 60;
our $headTime = "10";
#our $pickX = 2218;                                                                                                                   
our $pickX = 2208;
our $pickY = 0;
our $tmpDir = "/mnt/a";
#our $tmpDir = "~/tmp";                                                                                                               

eval{main(@ARGV)};

print $@ if $@;

## メイン関数                                                                                                                         
# @param @fileNames ファイル名のリスト                                                                                                
# @return なし                                                                                                                        
sub main{
  my (@fileNames) = @_;
  GD::Image->trueColor(1);
  my $outputDir = -d $fileNames[-1] ? pop @fileNames : "";
  $tmpDir = tempdir(CLEANUP=>1) unless -d $tmpDir;
  my @threads;
  for my $fileName(@fileNames){
    print "$fileName\n";
    next if -d $fileName;
    my ($dir, $costume, $title) = $fileName =~ /(.*)\/(.+)-(.+)\.mp4/;
    my ($headOffset, $frames, $width, $height) = createHead($fileName);
    print "headOffset:$headOffset,frames:$frames,width:$width,height:$height:\n";
    next if $headOffset == 0;
    my $startTime = formatTime($headOffset-10);
    my $endTime = formatTime($headOffset+$frames);
    print "$startTime - $endTime\n";
    my $cutDir = "$dir/cut/";
    $cutDir = "$tmpDir/cut/" if $tmpDir;
    make_path($cutDir, {chmod=>0777}) unless -d $cutDir;
    my $outputFile = "${cutDir}$costume-$title.mp4";
    print "$outputFile\n";
    my ($cropWidth, $cropHeight, $cropX, $cropY) =
      ($width > $height)
      ? (1920, 1080, 302, 0)
      : (1080, 1920, 0, 320);
    my $cropCmd = qq{ffmpeg -ss $startTime -to $endTime -i "$fileName" -async 1 -vf crop=w=$cropWidth:h=$cropHeight:x=$cropX:y=$cropY\
 -nostdin -y "$outputFile" < /dev/null &};
    print "$cropCmd\n";
    `$cropCmd`;
    push @threads, threads->create(sub{
      if ($outputDir) {
        my $mvCmd = qq{mv "$outputFile" "$outputDir"};
        print "outputFile:$outputFile\n";
        print `ls -l "$outputFile"`;
	print "outputDir:$outputDir\n";
        print `ls -l "$outputDir"`;
        print "$mvCmd\n";
        `$mvCmd`;
      } elsif ($tmpDir) {
        my $orgDir = dirname($fileName);
        my $resultDir = File::Spec->catfile($orgDir, 'cut');
        make_path($resultDir) unless -d $resultDir;
        my $mvCmd = qq{mv "$outputFile" "$resultDir"};
        print "outputFile:";
        print `ls -l "$outputFile"`;
        print "resultDir:";
        print `ls -l "$resultDir"`;
        print "$mvCmd\n";
        `$mvCmd`;
      }
    });
  }
  for my $thread(@threads){
    $thread->join();
  }
}

##                                                                                                                                    
# ファイル名からヘッドのオフセットとフレーム数を取得                                                                                  
# @param $fileName ファイル名                                                                                                         
# @return ($headOffset, # 冒頭からのオフセット（フレーム単位）                                                                        
#           $frames,    # フレーム数                                                                                                  
#           $width,     # 幅                                                                                                          
#           $height)    # 高さ                                                                                                        
sub createHead{
  my ($fileName) = @_;
  my ($dir, $costume, $title, $direction) = $fileName =~ /(.*)\/([^-]+)-([^-]+)(-([^-]+))?\.mp4/;
  print "dir:$dir,costume:$costume,title:$title\n";
  $direction = "" unless $direction;
  #print "$direction\n" if $direction;                                                                                                
  my $headOffset = 0;
  my $headDir = "$dir/head/$costume-$title/";
  $headDir = "$tmpDir/head/$costume-$title/" if $tmpDir;
  make_path($headDir, {chmod=>0777}) unless -d $headDir;
  my $cutCmd = qq{ffmpeg -i "$fileName" -ss 00:00:00 -to 00:00:$headTime -vcodec png -r $fps "${headDir}image_%05d.png" -y 2>%1 < /de\
v/null};
  print "$cutCmd\n";
  `$cutCmd`;
  my ($width, $height);
  for my $n(5..($fps*$headTime)) {
    my $imgFileName = sprintf("${headDir}image_%05d.png", $n);
    print "imgFileName:$imgFileName\n";
    my $img = new GD::Image($imgFileName);
    print "$n,";
    ($width, $height) = judge($img);
    if($width and $height){
      print "width:$width, height:$height \n";
      $headOffset = $n;
      last;
    }
  }
  remove_tree($headDir) if $headOffset;
  my $frames = getFrame($title);
  die "$title not found\n" unless $frames;

  if($frame==0){
    #my $bottomOffset = bottomOffset($fileName, $headOffset);                                                                         
    $frames = calcFrames($fileName, $headOffset);
  }

  print "headOffset:$headOffset, frames:$frames\n";
  return ($headOffset,  # 冒頭からのオフセット（フレーム単位）                                                                        
          $frames,      # フレーム数                                                                                                  
          $width,       # 幅                                                                                                          
          $height);     # 高さ                                                                                                        
}
# MVの内容からフレーム数を計算                                                                                                        
sub calcFrames{
  my ($fileName, $headOffset) = @_;
  my ($dir, $costume, $title, $direction) = $fileName =~ /(.*)\/([^-]+)-([^-]+)(-([^-]+))?\.mp4/;
  # my $bottomDir   = "$dir/bottom/$costume-$title/";                                                                                 
  # $bottomDir = "$tmpDir/bottom/$costume-$title/" if $tmpDir;                                                                        
  # make_path($bottomDir, {chmod=>0777}) unless -d $bottomDir;                                                                        

  # 下記の間にjudgeに引っかかるフレームが1秒以上存在する想定                                                                          
  my $minFrame = $fps * 60 * 1.75; ##1分45秒を最短と仮定した場合の最小フレーム数                                                      
  my $maxFrame = $fps * 60 * 2.5; ##2分30秒を最長と仮定した場合の最大フレーム数                                                       

}

# 曲名からフレーム数を取得                                                                                                            
sub getFrame{
  my ($title) = @_;
  return 8012 if $title eq "エヴリデイドリーム";
  return 8548 if $title eq "ギュっとMilkyWay";
  return 8105 if $title eq "S(mile)ING!" or $title eq "SmileING";
  return 8642 - 317 -1 if $title eq "もりのくにから";
  return 8258 if $title eq "風色メロディ";
  return 8349 -233 -1 if $title eq "LastKiss";
  return 8300 -170 -1 if $title eq "祈りの花";
  return 8446 -446 -1 if $title eq "You're stars shine on me";
  return 8072 -208 -1 if $title eq "恋のHamburg";
  return 8467 -210 -1 if $title eq "薄荷";
  return 8334 -200 -1 if $title eq "小さな恋の密室事件";
  return 8241 -233 -1 if $title eq "ましゅまろキッス";
  return 8225 -234 -1 if $title eq "おねだりShall We？";
  return 8375 -173 -1 if $title eq "Hotel Moonside";
  return 8139 -234 -1 if $title eq "ミツボシ";
  return 8557 -191 -1 if $title eq "never say never";
  return 8329 -232 -1 if $title eq "To my darling…";
  return 8103 -239 -1 if $title eq "Twilight sky";
  return 7977 -198 -1 if $title =~ /^DOKIDOKI/;
  return 8236 -130 -1 if $title =~ /あんずのうた/;
  return 8327 -237 -1 if $title =~ /華蕾夢ミル狂詩曲～魂ノ導～/;
  return 8224 -148 -1 if $title =~ /ショコラ・ティアラ/;
  return 8699 -234 -1 if $title =~ /Angel Breeze/;
  #die "$title not found\n";                                                                                                          
  return 0;
}

sub all{ my($f, @arg) = @_; for my $elm(@arg){ return 0 unless &$f($elm) } 1 }


# 判定関数                                                                                                                            
# @param $img GD::Imageオブジェクト                                                                                                   
# @return ($width, $height) 画像の幅と高さ                                                                                            
sub judge{
  my ($img) = @_;
  my ($width, $height) = $img->getBounds();
  my @pixels;
  if($width > $height){
    my $availableLeft = ($width - 1920) / 2;
    my $availableRight = $availableLeft + 1913;
    @pixels = map{[$img->rgb($img->getPixel($_, $height/2))]} $availableLeft .. $availableRight;
  }else{
    my $availableTop = ($height - 1920) / 2;
    my $availableBottom = $availableTop + 1913;
    @pixels = map{[$img->rgb($img->getPixel($width/2, $_))]} $availableTop .. $availableBottom;
  }
  #print(join(",", @$_), " ") for @pixels;                                                                                            
  #print Dumper(@pixels), "\n";                                                                                                       
  #return !all(sub{ all(sub{ print"$_[0]," if $_[0]!=29; $_[0]==29 }, @{$_[0]})}, @pixels);                                           
  # return ($width, $height)                                                                                                          
  #   if !all(sub{ all(sub{ print"$_[0]," if $_[0]!=29; $_[0]==29 }, @{$_[0]})}, @pixels);                                            
  return ($width, $height)
      if !all(sub{ all(sub{ $_[0]==27 or $_[0]==28 or$_[0]==29 or $_[0]==30 }, @{$_[0]})}, @pixels);
}

sub formatTime{
  my ($frm) = @_;
  #return sprintf("%02d:%02d:%02d.%02d",$frm/60/60/60,$frm/60/60,$frm/60,($frm*60)/100);                                              
  my $hour = sprintf("%d", $frm/60/60/60);
  $frm -= $hour*60*60*60;
  my $min = sprintf("%d", $frm/60/60);
  $frm -= $min*60*60;
  my $sec = sprintf("%d", $frm/60);
  $frm -= $sec*60;
  my $msec = sprintf("%d", ($frm*100)/60);
  return sprintf("%02d:%02d:%02d.%02d",$hour,$min,$sec,$msec);
}

